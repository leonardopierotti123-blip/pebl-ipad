//* -*- mode:C++; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*- */
/////////////////////////////////////////////////////////////////////////////////
//    Name:       platforms/ios/PEBLiOSRunLoop.cpp
//    Purpose:    Launcher/script loop used instead of main() logic on iOS
//    License:    GPL 2
//
//     This file is part of the PEBL project.
//
//    PEBL is free software; you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation; either version 2 of the License, or
//    (at your option) any later version.
//
//  iOS has no shell, no command line and does not allow an app to exit or
//  spawn processes.  Instead of the desktop launcher (a separate program that
//  forks pebl2), the iOS app alternates, inside one process, between:
//
//    1. ios-launcher.pbl (in the app bundle): a touch UI listing the battery,
//       which writes the user's choice to a small request file and returns;
//    2. the chosen script, run with the equivalent of
//         pebl2 <script> -s <subject> --language <xx> [--pfile <file>]
//       with the working directory set to the script's own folder.
//
//  Fatal errors, ExitQuietly() and the four-finger abort gesture throw
//  PEBLScriptExit (see utility/PError.h), which is caught here.
////////////////////////////////////////////////////////////////////////////////

#ifdef PEBL_IOS

#include "PEBLiOS.h"

#include "../../apps/Globals.h"
#include "../../base/Loader.h"
#include "../../base/PNode.h"
#include "../../base/Variant.h"
#include "../../utility/PError.h"
#include "../../utility/PEBLUtility.h"
#include "../sdl/PlatformEnvironment.h"

#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>

using std::cerr;
using std::endl;

//Defined in apps/PEBL.cpp
extern Loader * myLoader;
extern PNode * head;
extern PlatformEnvironment * myEnv;
int PEBLInterpret(int argc, std::vector<std::string> argv);


/// Frees everything a script created, so that the next script starts from
/// a clean interpreter.  Mirrors the native cleanup in PEBLInterpret(), but
/// keeps SDL initialised (re-initialising UIKit video is fragile).
void PEBLiOSCleanupScript()
{
    try
        {
            //Delete the evaluator first: its local variables (child widgets)
            //must go before the globals (parent windows).
            if(::myEval)
                {
                    delete ::myEval;
                    ::myEval = NULL;
                }

            Evaluator::gGlobalVariableMap.Destroy();

            if(myLoader)
                {
                    delete myLoader;
                    myLoader = NULL;
                }
            if(myEnv)
                {
                    delete myEnv;
                    myEnv = NULL;
                }
            Evaluator::mFunctionMap.Destroy();
        }
    catch(std::exception & e)
        {
            cerr << "Error while cleaning up script: " << e.what() << endl;
        }

    head = NULL;
    Evaluator::gEvalNode = NULL;
    while(Evaluator::gCallStack.Size() > 0)
        Evaluator::gCallStack.Pop();
    Evaluator::gPath.Clear();

    PEBLiOS::SetKeyboardVisible(false);
    PEBLiOS::ResetGestures();
}


/// Globals every script can rely on, set before each run (the global
/// variable map is wiped by the previous cleanup).
static void SetGlobals(const std::string & message, int touchMode)
{
    std::string resources = PEBLiOS::GetResourcePath();
    std::string documents = PEBLiOS::GetDocumentsPath();

    VariableMap & g = Evaluator::gGlobalVariableMap;
    g.AddVariable("gPEBLResourcePath",      Variant(resources + "/"));
    g.AddVariable("gPEBLBasePath",          Variant(resources + "/"));
    g.AddVariable("gPEBLDocumentsPath",     Variant(documents + "/"));
    g.AddVariable("gPEBLBatteryPath",       Variant(documents + "/battery/"));
    g.AddVariable("gPEBLiOSRequestFile",    Variant(PEBLiOS::GetRequestFilePath()));
    g.AddVariable("gPEBLiOSDeviceLanguage", Variant(PEBLiOS::GetDeviceLanguage()));
    g.AddVariable("gPEBLiOSMessage",        Variant(message));
    g.AddVariable("gPEBLiOSTouchMode",      Variant(touchMode));
    g.AddVariable("gWorkingDirectory",      PEBLUtility::GetWorkingDirectory());
}


/// Runs one script; never lets an exception escape.
/// Returns the script's exit code.  'message' receives the reason the script
/// stopped early (empty after a normal end); 'failed' is true for errors.
static int RunScript(const std::vector<std::string> & args,
                     const std::string & workingDir,
                     const std::string & launcherMessage,
                     int touchMode,
                     std::string & message,
                     bool & failed)
{
    failed = false;
    message = "";

    if(workingDir != "" && chdir(workingDir.c_str()) != 0)
        {
            cerr << "Unable to change to directory [" << workingDir << "]\n";
        }

    SetGlobals(launcherMessage, touchMode);

    int code = 0;
    try
        {
            code = PEBLInterpret((int)args.size(), args);
        }
    catch(PEBLScriptExit & e)
        {
            code = e.GetCode();
            failed = e.IsError();
            message = e.what();
            if(message == "") message = "stopped";
            cerr << "Script ended early: " << message << endl;
            PEBLiOSCleanupScript();
        }
    catch(std::exception & e)
        {
            code = 1;
            failed = true;
            message = std::string("Internal error: ") + e.what();
            cerr << message << endl;
            PEBLiOSCleanupScript();
        }

    //Make sure data files written by the script reach the disk.
    sync();
    return code;
}


static std::string OneLine(std::string s)
{
    for(size_t i = 0; i < s.size(); i++)
        if(s[i] == '\n' || s[i] == '\r' || s[i] == '|') s[i] = ' ';
    return s;
}


int PEBLiOSRunLoop(int argc, char *argv[])
{
    PEBLiOS::Initialize();     //SDL hints, lifecycle hooks; must precede SDL_Init.
    PEBLiOS::InstallBattery(); //copies the battery to Documents on first run / update.

    const std::string exe = (argc > 0) ? argv[0] : "pebl2";
    const std::string launcher = PEBLiOS::GetResourcePath() + "/ios-launcher.pbl";
    const std::string documents = PEBLiOS::GetDocumentsPath();

    //Status line shown by the launcher: "<KIND>|<script>|<detail>"
    std::string status = "";
    int launcherFailures = 0;

    while(!PEBLiOS::IsTerminating())
        {
            //----- 1. Launcher ------------------------------------------------
            PEBLiOS::DeleteRequest();

            std::vector<std::string> largs;
            largs.push_back(exe);
            largs.push_back(launcher);
            largs.push_back("--fullscreen");

            std::string lmessage;
            bool lfailed = false;
            RunScript(largs, documents, status, 1, lmessage, lfailed);

            if(PEBLiOS::IsTerminating()) break;

            if(lfailed)
                {
                    //A broken launcher would loop forever; give up after a few tries.
                    launcherFailures++;
                    status = "ERROR|ios-launcher.pbl|" + OneLine(lmessage);
                    if(launcherFailures >= 3)
                        {
                            PEBLiOS::ShowFatalMessage("PEBL launcher failed", lmessage);
                            return 1;
                        }
                    continue;
                }
            launcherFailures = 0;

            PEBLiOS::Request req;
            if(!PEBLiOS::ReadRequest(req))
                {
                    status = "";
                    continue;  //nothing chosen; show the launcher again
                }
            PEBLiOS::DeleteRequest();

            //----- 2. The selected script -------------------------------------
            std::vector<std::string> sargs;
            sargs.push_back(exe);
            sargs.push_back(req.script);
            if(req.subnum != "")
                {
                    sargs.push_back("-s");
                    sargs.push_back(req.subnum);
                }
            if(req.language != "")
                {
                    sargs.push_back("--language");
                    sargs.push_back(req.language);
                }
            if(req.pfile != "")
                {
                    sargs.push_back("--pfile");
                    sargs.push_back(req.pfile);
                }
            for(size_t k = 0; k < req.values.size(); k++)
                {
                    sargs.push_back("-v");
                    sargs.push_back(req.values[k]);
                }
            sargs.push_back("--fullscreen");

            std::string smessage;
            bool sfailed = false;
            int code = RunScript(sargs, PEBLUtility::StripFile(req.script),
                                 "", req.touchMode, smessage, sfailed);

            std::string name = PEBLUtility::GetBaseFileName(req.script);
            if(sfailed)
                status = "ERROR|" + name + "|" + OneLine(smessage);
            else if(smessage != "")
                status = "STOPPED|" + name + "|" + OneLine(smessage);
            else
                status = "DONE|" + name + "|" + std::to_string(code);
        }

    return 0;
}

#endif
