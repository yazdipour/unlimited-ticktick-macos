/*
 * Frida hook for TickTick macOS.
 *
 * Forces TickTick macOS user entitlement fields to a non-pro state.
 *
 * WPF equivalent:
 *   ticktick_WPF.Models.UserModel.proEndDate = 1990
 *   ticktick_WPF.Models.UserModel.pro = false
 */

'use strict';

if (!ObjC.available) {
  throw new Error('Objective-C runtime is not available in this process');
}

const proValue = ptr('0x1');
const forcedProEndDate = ObjC.classes.NSDate.dateWithTimeIntervalSince1970_(4070908800);
const forcedProEndDateText = forcedProEndDate.toString();

function hookMethod(className, selector, handlers) {
  const klass = ObjC.classes[className];
  if (!klass) {
    console.log(`[skip] ${className} not found`);
    return false;
  }

  const method = klass[selector];
  if (!method) {
    console.log(`[skip] ${className} ${selector} not found`);
    return false;
  }

  Interceptor.attach(method.implementation, handlers);
  console.log(`[hook] ${className} ${selector}`);
  return true;
}

hookMethod('TTUserModel', '- setIsPro:', {
  onEnter(args) {
    const original = args[2].toInt32();
    args[2] = proValue;
    console.log(`[setIsPro:] ${original} -> false`);
  }
});

hookMethod('TTUserModel', '- isPro', {
  onLeave(retval) {
    const original = retval.toInt32();
    retval.replace(proValue);
    console.log(`[isPro] ${original} -> false`);
  }
});

hookMethod('TTUserModel', '- setProEndDate:', {
  onEnter(args) {
    const original = args[2].isNull() ? 'nil' : new ObjC.Object(args[2]).toString();
    args[2] = forcedProEndDate;
    console.log(`[setProEndDate:] ${original} -> ${forcedProEndDateText}`);
  }
});

hookMethod('TTUserModel', '- proEndDate', {
  onLeave(retval) {
    const original = retval.isNull() ? 'nil' : new ObjC.Object(retval).toString();
    retval.replace(forcedProEndDate);
    console.log(`[proEndDate] ${original} -> ${forcedProEndDateText}`);
  }
});

console.log('[ready] TickTick pro=false / proEndDate=1990 forcing is active');
