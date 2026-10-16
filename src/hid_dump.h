#ifndef _HID_DUMP_H_
#define _HID_DUMP_H_

#include <stdio.h>
#include <string.h>

// The largest report we will dump/keep around.
#define HID_DUMP_PACKET_SZ 64

/*
 * The button bits of a report: bits 0..31 in the four bytes after the report
 * ID, bits 32..39 in the fifth byte. Bit N is button number N in the name
 * table (bit 0 = SHIFT). Bytes beyond the reported length are treated as zero,
 * so a short report cannot be read past its end.
 */
unsigned long long hid_dump_button_mask( const unsigned char * packet, int length );

/*
 * Prints a HID report only when it differs from the previously dumped one,
 * and decodes the fields of the A-series protocol that komplement already
 * understands (the button mask and the 4D dial position). This is what the
 * `-d` option of the komplement tool uses; it exists so that the controls
 * which are not handled yet (rotary rotation and touch, 4D directions, ...)
 * can be located in the report without a hex editor.
 *
 * `stamp_ms` is a caller supplied monotonic timestamp, printed as-is.
 *
 * Returns 1 when something was printed, 0 when the report was a duplicate.
 */
int hid_dump_packet( const unsigned char * packet, int length, long long stamp_ms );

#endif /* _HID_DUMP_H_ */
