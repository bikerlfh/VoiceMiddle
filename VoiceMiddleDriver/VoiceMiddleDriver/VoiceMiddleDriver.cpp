//
//  VoiceMiddleDriver.cpp
//  VoiceMiddleDriver
//
//  Created by LuisMo on 2026-05-11.
//

#include <os/log.h>

#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>

#include "VoiceMiddleDriver.h"

kern_return_t
IMPL(VoiceMiddleDriver, Start)
{
    kern_return_t ret;
    ret = Start(provider, SUPERDISPATCH);
    os_log(OS_LOG_DEFAULT, "Hello World");
    return ret;
}
