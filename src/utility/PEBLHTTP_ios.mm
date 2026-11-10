//* -*- mode:ObjC++; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*- */
/////////////////////////////////////////////////////////////////////////////////
//    Name:       utility/PEBLHTTP_ios.mm
//    Purpose:    PEBLHTTP implemented with NSURLSession (iOS has no libcurl)
//    License:    GPL 2
//
//     This file is part of the PEBL project.
//
//    PEBL is free software; you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation; either version 2 of the License, or
//    (at your option) any later version.
//
//  Behaviour matches the libcurl implementation in PEBLHTTP.cpp:
//   - GetHTTPFile / GetHTTPText fetch <host><path> on the given port;
//   - PostHTTP / PostMulti send multipart/form-data with the name/value pairs
//     in 'args', the file, a 'filename' field and 'submit=send', and return
//     the server's response text.
//  Requests are synchronous, as the scripts expect.
////////////////////////////////////////////////////////////////////////////////

#ifdef PEBL_IOS

#import <Foundation/Foundation.h>

#include "PEBLHTTP.h"   //defines PEBL_NSURL, so test HTTP_LIB only after this

#endif

#if defined(PEBL_IOS) && defined(PEBL_HTTP) && (HTTP_LIB == PEBL_NSURL)
#include "PError.h"
#include "../base/PList.h"
#include "../base/PComplexData.h"
#include "../utility/rc_ptrs.h"

#include <iostream>
#include <string>

namespace
{
    const NSTimeInterval kTimeout = 60.0;

    NSString * NS(const std::string & s)
    {
        return [NSString stringWithUTF8String:s.c_str()];
    }

    /// <scheme>://<host>[:port]<path>, following the curl version's rules.
    NSURL * BuildURL(const std::string & host, int port, const std::string & path)
    {
        std::string h = host;
        std::string scheme;
        size_t p = h.find("://");
        if(p != std::string::npos)
            {
                scheme = h.substr(0, p);
                h = h.substr(p + 3);
            }
        else
            {
                scheme = (port == 443) ? "https" : "http";
            }
        while(!h.empty() && h[h.size()-1] == '/' && !path.empty() && path[0] == '/')
            h.erase(h.size()-1);

        bool defaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443);
        bool hostHasPort = h.find(':') != std::string::npos;
        std::string url = scheme + "://" + h;
        if(!defaultPort && !hostHasPort && port > 0)
            url += ":" + std::to_string(port);
        url += path;

        NSString * s = NS(url);
        NSURL * u = [NSURL URLWithString:s];
        if(!u)
            {
                u = [NSURL URLWithString:[s stringByAddingPercentEncodingWithAllowedCharacters:
                                          [NSCharacterSet URLFragmentAllowedCharacterSet]]];
            }
        return u;
    }

    /// Runs a request synchronously.  Returns the HTTP status (0 on failure).
    int Perform(NSURLRequest * request, NSData ** body)
    {
        __block NSData * result = nil;
        __block NSInteger status = 0;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);

        NSURLSessionDataTask * task =
            [[NSURLSession sharedSession] dataTaskWithRequest:request
                completionHandler:^(NSData * data, NSURLResponse * response, NSError * error)
                {
                    if(error)
                        {
                            std::cerr << "HTTP error: " << [[error localizedDescription] UTF8String] << "\n";
                        }
                    if([response isKindOfClass:[NSHTTPURLResponse class]])
                        status = [(NSHTTPURLResponse *)response statusCode];
                    result = data;
                    dispatch_semaphore_signal(done);
                }];
        [task resume];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

        if(body) *body = result;
        return (int)status;
    }

    void AppendField(NSMutableData * body, NSString * boundary, NSString * name, NSString * value)
    {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                           boundary, name, value] dataUsingEncoding:NSUTF8StringEncoding]];
    }

    /// Multipart POST shared by PostHTTP and PostMulti.
    std::string PostForm(const std::string & host, int port, const std::string & page,
                         Variant args, const std::string & fileField,
                         const std::string & uploadName, int & statusOut)
    {
        NSURL * url = BuildURL(host, port, page);
        if(!url)
            {
                std::cerr << "HTTP: invalid URL for host " << host << "\n";
                statusOut = 0;
                return "";
            }

        NSString * boundary = [NSString stringWithFormat:@"----PEBLBoundary%@", [[NSUUID UUID] UUIDString]];
        NSMutableData * body = [NSMutableData data];

        PError::AssertType(args, PEAT_LIST, "PostHTTP arguments must be a list");
        PList * dataList = (PList*)(args.GetComplexData()->GetPEBLObject().get());
        std::vector<Variant>::iterator p1 = dataList->Begin();
        std::vector<Variant>::iterator p1end = dataList->End();
        while(p1 != p1end)
            {
                std::string head = *p1;
                p1++;
                if(p1 == p1end) break;
                std::string value = *p1;
                p1++;
                AppendField(body, boundary, NS(head), NS(value));
            }

        NSString * path = NS(uploadName);
        NSData * fileData = [NSData dataWithContentsOfFile:path];
        if(!fileData)
            {
                std::cerr << "HTTP: could not read file to upload: " << uploadName << "\n";
                fileData = [NSData data];
            }
        [body appendData:[[NSString stringWithFormat:
                           @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
                           @"Content-Type: application/octet-stream\r\n\r\n",
                           boundary, NS(fileField), [path lastPathComponent]]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

        AppendField(body, boundary, @"filename", path);
        AppendField(body, boundary, @"submit", @"send");
        [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary]
                          dataUsingEncoding:NSUTF8StringEncoding]];

        NSMutableURLRequest * req = [NSMutableURLRequest requestWithURL:url
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:kTimeout];
        [req setHTTPMethod:@"POST"];
        [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
            forHTTPHeaderField:@"Content-Type"];
        [req setValue:@"PEBL-iOS" forHTTPHeaderField:@"User-Agent"];
        [req setHTTPBody:body];

        NSData * response = nil;
        statusOut = Perform(req, &response);

        std::string text;
        if(response)
            {
                NSString * s = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
                if(s) text = [s UTF8String];
            }
        return text;
    }
}


PEBLHTTP::PEBLHTTP(Variant host, int port)
{
    mHost = host;
    mPort = port;
    mFile = NULL;
    mStatus = 0;
    mByteCount = 0;
}


PEBLHTTP::~PEBLHTTP()
{
}


int PEBLHTTP::GetHTTPFile(Variant filename, Variant savename)
{
    @autoreleasepool
        {
            NSURL * url = BuildURL(mHost.GetString(), mPort, filename.GetString());
            if(!url) { mStatus = 0; return mStatus; }

            NSMutableURLRequest * req = [NSMutableURLRequest requestWithURL:url
                                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                            timeoutInterval:kTimeout];
            [req setValue:@"PEBL-iOS" forHTTPHeaderField:@"User-Agent"];

            NSData * data = nil;
            mStatus = Perform(req, &data);

            //Like the curl version, the file is created even if the download failed.
            if(!data) data = [NSData data];
            [data writeToFile:NS(savename.GetString()) atomically:YES];
            mByteCount = (int)[data length];
        }
    return mStatus;
}


std::string PEBLHTTP::GetHTTPText(Variant filename)
{
    @autoreleasepool
        {
            NSURL * url = BuildURL(mHost.GetString(), mPort, filename.GetString());
            if(!url) { mStatus = 0; return mText; }

            NSMutableURLRequest * req = [NSMutableURLRequest requestWithURL:url
                                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                            timeoutInterval:kTimeout];
            [req setValue:@"PEBL-iOS" forHTTPHeaderField:@"User-Agent"];

            NSData * data = nil;
            mStatus = Perform(req, &data);
            if(data)
                {
                    NSString * s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if(!s) s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
                    if(s) mText = [s UTF8String];
                    mByteCount = (int)[data length];
                }
        }
    return mText;
}


Variant PEBLHTTP::PostHTTP(Variant pagename, Variant args, Variant uploadname)
{
    @autoreleasepool
        {
            mText = PostForm(mHost.GetString(), mPort, pagename.GetString(), args,
                             "sendfile", uploadname.GetString(), mStatus);
        }
    return Variant(mText);
}


Variant PEBLHTTP::PostMulti(Variant pagename, Variant args, Variant uploadname, Variant form)
{
    @autoreleasepool
        {
            mText = PostForm(mHost.GetString(), mPort, pagename.GetString(), args,
                             form.GetString(), uploadname.GetString(), mStatus);
        }
    return Variant(mText);
}

#endif
