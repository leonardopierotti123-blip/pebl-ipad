//* -*- mode:C++; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*- */
/////////////////////////////////////////////////////////////////////////////////
//    Name:       platforms/ios/PEBLiOS.h
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
#ifndef __PEBLIOS_H__
#define __PEBLIOS_H__

#ifdef PEBL_IOS

#include <string>
#include <vector>

union SDL_Event;

namespace PEBLiOS
{
    /// Sets SDL hints, redirects the log to Documents/logs and hooks app
    /// lifecycle events.  Call once, before anything else touches SDL.
    void Initialize();

    /// Copies the bundled battery to Documents/battery on first launch, and
    /// refreshes the scripts after an app update (never touching data/ folders
    /// or user parameter files).
    void InstallBattery();

    /// Read-only resources inside the .app bundle (media/, pebl-lib/, ...), no trailing slash.
    std::string GetResourcePath();
    /// The app's Documents folder (visible in the Files app), no trailing slash.
    std::string GetDocumentsPath();
    /// Where ios-launcher.pbl writes the user's choice.
    std::string GetRequestFilePath();
    /// Two-letter code of the iPad's preferred language, e.g. "it".
    std::string GetDeviceLanguage();

    /// The launcher's choice: which script to run and how.
    struct Request
    {
        std::string script;     // absolute path of the .pbl file
        std::string subnum;     // participant code (-s)
        std::string language;   // --language
        std::string pfile;      // --pfile (file name inside params/), may be empty
        std::vector<std::string> values;  // extra -v values
        int touchMode;          // 1: replace keyboard response modes by touch (gPEBLiOSTouchMode)
        Request() : touchMode(1) {}
    };
    bool ReadRequest(Request & req);
    void DeleteRequest();

    /// True once iOS has told the app it is about to be terminated.
    bool IsTerminating();

    /// Native alert for errors that leave no PEBL window to draw in.
    void ShowFatalMessage(const std::string & title, const std::string & message);

    /// LaunchFile(): web URLs open in Safari, local files in the Files app.
    int OpenURLOrFile(const std::string & target);

    /// Shows/hides the on-screen keyboard (SDL text input).
    void SetKeyboardVisible(bool visible);

    /// Touch gestures: three-finger tap = toggle keyboard,
    /// four fingers held for two seconds = abort the running script.
    void HandleFingerEvent(const SDL_Event & event);
    void CheckAbortGesture();
    void ResetGestures();
}

#endif
#endif
