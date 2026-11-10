//* -*- mode:ObjC++; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*- */
/////////////////////////////////////////////////////////////////////////////////
//    Name:       platforms/ios/PEBLiOS.mm
//    Purpose:    iOS/iPadOS glue (paths, battery install, gestures, keyboard)
//    License:    GPL 2
//
//     This file is part of the PEBL project.
//
//    PEBL is free software; you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation; either version 2 of the License, or
//    (at your option) any later version.
////////////////////////////////////////////////////////////////////////////////

#ifdef PEBL_IOS

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "PEBLiOS.h"
#include "../../utility/PError.h"

#include "SDL.h"

#include <cstdio>
#include <ctime>
#include <fstream>
#include <iostream>
#include <set>
#include <sys/stat.h>

namespace
{
    bool gTerminating = false;

    //Gesture tracking
    std::set<SDL_FingerID> gFingers;
    Uint32 gTapStart = 0;
    size_t gTapMaxFingers = 0;
    Uint32 gAbortStart = 0;

    const Uint32 kTapMaxMs   = 700;   //three-finger tap must be shorter than this
    const Uint32 kAbortMs    = 2000;  //four-finger hold must be longer than this

    std::string ToStd(NSString * s)
    {
        return s ? std::string([s UTF8String]) : std::string();
    }

    int SDLCALL LifecycleWatch(void * userdata, SDL_Event * event)
    {
        switch(event->type)
            {
            case SDL_APP_TERMINATING:
                gTerminating = true;
                std::cerr << "iOS: app terminating\n";
                break;
            case SDL_APP_WILLENTERBACKGROUND:
                //Timing is meaningless while the app is in the background;
                //leave a trace in the log so data can be checked.
                std::cerr << "iOS WARNING: app entering background at "
                          << SDL_GetTicks() << " ms\n";
                break;
            case SDL_APP_DIDENTERFOREGROUND:
                std::cerr << "iOS: app back in foreground at " << SDL_GetTicks() << " ms\n";
                break;
            case SDL_APP_LOWMEMORY:
                std::cerr << "iOS WARNING: low memory\n";
                break;
            default:
                break;
            }
        return 1;
    }

    /// Copies src -> dst recursively.  Existing files are replaced only when
    /// 'refresh' is set, and never inside data/ folders or for *.par.json.
    void MergeCopy(NSString * src, NSString * dst, BOOL refresh)
    {
        NSFileManager * fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator * en = [fm enumeratorAtPath:src];
        [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];

        NSString * rel;
        while((rel = [en nextObject]))
            {
                NSString * from = [src stringByAppendingPathComponent:rel];
                NSString * to   = [dst stringByAppendingPathComponent:rel];

                BOOL isDir = NO;
                [fm fileExistsAtPath:from isDirectory:&isDir];
                if(isDir)
                    {
                        [fm createDirectoryAtPath:to withIntermediateDirectories:YES attributes:nil error:nil];
                        continue;
                    }

                BOOL protectedFile =
                    [[rel pathComponents] containsObject:@"data"] ||
                    [rel hasSuffix:@".par.json"];

                if([fm fileExistsAtPath:to])
                    {
                        if(!refresh || protectedFile) continue;
                        [fm removeItemAtPath:to error:nil];
                    }

                NSError * err = nil;
                if(![fm copyItemAtPath:from toPath:to error:&err])
                    {
                        std::cerr << "iOS: could not copy " << ToStd(rel) << ": "
                                  << ToStd([err localizedDescription]) << "\n";
                    }
            }
    }
}


namespace PEBLiOS
{

std::string GetResourcePath()
{
    return ToStd([[NSBundle mainBundle] resourcePath]);
}


std::string GetDocumentsPath()
{
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return ToStd([paths firstObject]);
}


std::string GetRequestFilePath()
{
    return ToStd([NSTemporaryDirectory() stringByAppendingPathComponent:@"pebl-ios-request.txt"]);
}


std::string GetDeviceLanguage()
{
    NSString * pref = [[NSLocale preferredLanguages] firstObject];
    std::string lang = pref ? ToStd(pref) : "en";
    lang = lang.substr(0, 2);
    for(size_t i = 0; i < lang.size(); i++) lang[i] = (char)tolower(lang[i]);
    return lang;
}


void Initialize()
{
    @autoreleasepool
        {
            std::string docs = GetDocumentsPath();

            //Keep the console output of the last session in Documents/logs,
            //so problems can be diagnosed without Xcode.
            std::string logdir = docs + "/logs";
            mkdir(logdir.c_str(), 0755);
            std::string logfile = logdir + "/pebl-log.txt";
            if(freopen(logfile.c_str(), "w", stderr))
                {
                    setvbuf(stderr, NULL, _IOLBF, 0);
                }
            time_t now = time(NULL);
            std::cerr << "PEBL for iPad, session started " << ctime(&now);
            std::cerr << "Resources: " << GetResourcePath() << "\nDocuments: " << docs << "\n";
        }

    //Landscape only (also enforced in Info.plist).
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    //Swipes from the screen edges must not send the participant home.
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
    //Metal is the supported GPU API on iOS.
    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
    //Touches act as left mouse button events (PEBL's click handling) ...
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    //... but mouse/trackpad input must not create fake touches.
    SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
    //Play sound even when the silent switch is on.
    SDL_SetHint(SDL_HINT_AUDIO_CATEGORY, "playback");
    //Keep the screen awake during experiments.
    SDL_SetHint(SDL_HINT_VIDEO_ALLOW_SCREENSAVER, "0");

    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER) < 0)
        {
            std::cerr << "SDL_Init failed: " << SDL_GetError() << "\n";
        }
    SDL_DisableScreenSaver();
    SDL_AddEventWatch(LifecycleWatch, NULL);
}


void InstallBattery()
{
    @autoreleasepool
        {
            NSFileManager * fm = [NSFileManager defaultManager];
            NSString * docs = [NSString stringWithUTF8String:GetDocumentsPath().c_str()];
            NSString * src = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"battery"];
            NSString * dst = [docs stringByAppendingPathComponent:@"battery"];
            NSString * marker = [docs stringByAppendingPathComponent:@"logs/.battery-version"];

            NSDictionary * info = [[NSBundle mainBundle] infoDictionary];
            NSString * version = [NSString stringWithFormat:@"%@ (%@)",
                                  info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];

            NSString * installed = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil];
            BOOL firstRun = ![fm fileExistsAtPath:dst];
            BOOL updated = !installed || ![installed isEqualToString:version];

            if(firstRun || updated)
                {
                    std::cerr << "iOS: installing battery " << ToStd(version)
                              << (firstRun ? " (first run)\n" : " (update)\n");
                    MergeCopy(src, dst, updated && !firstRun);
                    [version writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            else
                {
                    //Restore anything the user deleted, without overwriting.
                    if(![fm fileExistsAtPath:[dst stringByAppendingPathComponent:@"battery.txt"]])
                        MergeCopy(src, dst, NO);
                }

            //A folder for the user's own experiments.
            [fm createDirectoryAtPath:[docs stringByAppendingPathComponent:@"my-experiments"]
                withIntermediateDirectories:YES attributes:nil error:nil];
        }
}


bool ReadRequest(Request & req)
{
    req = Request();
    std::ifstream in(GetRequestFilePath().c_str());
    if(!in) return false;

    std::string line;
    while(std::getline(in, line))
        {
            if(!line.empty() && line[line.size()-1] == '\r') line.erase(line.size()-1);
            size_t eq = line.find('=');
            if(eq == std::string::npos) continue;
            std::string key = line.substr(0, eq);
            std::string val = line.substr(eq + 1);

            if(key == "script")        req.script = val;
            else if(key == "subnum")   req.subnum = val;
            else if(key == "language") req.language = val;
            else if(key == "pfile")    req.pfile = val;
            else if(key == "value")    req.values.push_back(val);
            else if(key == "touch")    req.touchMode = (val == "0") ? 0 : 1;
        }

    if(req.script == "") return false;
    struct stat st;
    if(stat(req.script.c_str(), &st) != 0)
        {
            std::cerr << "iOS: requested script does not exist: " << req.script << "\n";
            return false;
        }
    return true;
}


void DeleteRequest()
{
    remove(GetRequestFilePath().c_str());
}


bool IsTerminating()
{
    return gTerminating;
}


void ShowFatalMessage(const std::string & title, const std::string & message)
{
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, title.c_str(), message.c_str(), NULL);
}


int OpenURLOrFile(const std::string & target)
{
    std::string url = target;
    if(url.find("://") == std::string::npos)
        {
            //A local file: reveal it in the Files app.
            url = "shareddocuments://" + target;
        }
    return SDL_OpenURL(url.c_str()) == 0 ? 1 : 0;
}


void SetKeyboardVisible(bool visible)
{
    if(visible)
        {
            if(!SDL_IsTextInputActive()) SDL_StartTextInput();
        }
    else
        {
            if(SDL_IsTextInputActive()) SDL_StopTextInput();
        }
}


void ResetGestures()
{
    gFingers.clear();
    gTapStart = 0;
    gTapMaxFingers = 0;
    gAbortStart = 0;
}


void HandleFingerEvent(const SDL_Event & event)
{
    Uint32 now = SDL_GetTicks();

    if(event.type == SDL_FINGERDOWN)
        {
            if(gFingers.empty())
                {
                    gTapStart = now;
                    gTapMaxFingers = 0;
                }
            gFingers.insert(event.tfinger.fingerId);
            if(gFingers.size() > gTapMaxFingers) gTapMaxFingers = gFingers.size();
            if(gFingers.size() >= 4 && gAbortStart == 0) gAbortStart = now;
        }
    else if(event.type == SDL_FINGERUP)
        {
            gFingers.erase(event.tfinger.fingerId);
            if(gFingers.size() < 4) gAbortStart = 0;

            if(gFingers.empty())
                {
                    if(gTapMaxFingers == 3 && now - gTapStart < kTapMaxMs)
                        {
                            SetKeyboardVisible(!SDL_IsTextInputActive());
                        }
                    gTapMaxFingers = 0;
                }
        }
}


void CheckAbortGesture()
{
    if(gAbortStart == 0) return;

    //If iOS swallowed some FINGERUP events, trust SDL's live finger count.
    int live = 0;
    for(int d = 0; d < SDL_GetNumTouchDevices(); d++)
        live += SDL_GetNumTouchFingers(SDL_GetTouchDevice(d));
    if(live < 4)
        {
            ResetGestures();
            return;
        }

    if(SDL_GetTicks() - gAbortStart >= kAbortMs)
        {
            ResetGestures();
            PError::ExitQuietly("Stopped by the experimenter (four-finger hold).", 0);
        }
}

} // namespace PEBLiOS

#endif
