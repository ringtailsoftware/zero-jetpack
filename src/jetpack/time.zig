extern fn getTimeUs() u32;

var startTime: u32 = 0;

pub fn initTime() void {
    startTime = getTimeUs();
}

pub fn millis() u32 {
    return (getTimeUs() - startTime) / 1000;
}
