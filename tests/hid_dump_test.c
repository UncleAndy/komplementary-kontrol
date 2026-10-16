/*
 * Test for the -d packet dump: synthetic reports must be printed on the first
 * call and on every change, and must stay silent when nothing changed.
 *
 * Built and run by the checkPhase of the flake (no hardware needed):
 *   cc -Wall -Isrc -o hid_dump_test tests/hid_dump_test.c src/hid_dump.c
 */
#include <stdio.h>
#include <string.h>

#include "hid_dump.h"
#include "button_names.h"

static int checks = 0;

#define CHECK(cond) \
    do { \
        checks++; \
        if (!(cond)) { \
            printf( "FAIL (line %d): %s\n", __LINE__, #cond ); \
            return 1; \
        } \
    } while (0)

int main( void )
{
    unsigned char base[ 30 ];
    memset( base, 0, sizeof base );
    base[ 0 ] = 0x01;

    // The first report is always shown, a repeat of it is not.
    CHECK( hid_dump_packet( base, 30, 0 ) == 1 );
    CHECK( hid_dump_packet( base, 30, 10 ) == 0 );

    // A single changed byte somewhere in the packet must be reported.
    unsigned char turned[ 30 ];
    memcpy( turned, base, sizeof turned );
    turned[ 25 ] = 0x03;
    CHECK( hid_dump_packet( turned, 30, 20 ) == 1 );
    CHECK( hid_dump_packet( turned, 30, 30 ) == 0 );

    // Turning further back to zero must be reported as well.
    CHECK( hid_dump_packet( base, 30, 40 ) == 1 );

    // A different byte, e.g. a touch sensor.
    unsigned char touched[ 30 ];
    memcpy( touched, base, sizeof touched );
    touched[ 26 ] = 0x01;
    CHECK( hid_dump_packet( touched, 30, 50 ) == 1 );
    CHECK( hid_dump_packet( touched, 30, 60 ) == 0 );

    // The length is part of the state: a shorter report is a change.
    CHECK( hid_dump_packet( touched, 28, 70 ) == 1 );
    CHECK( hid_dump_packet( touched, 28, 80 ) == 0 );

    // Trailing bytes are not part of the comparison, only the reported length.
    unsigned char longer[ 30 ];
    memcpy( longer, touched, sizeof longer );
    longer[ 29 ] = 0xff;
    CHECK( hid_dump_packet( longer, 28, 90 ) == 0 );

    // The button mask covers the fifth byte too: on an A49 bit 32 is the touch
    // sensor of Rotary8 and bit 33 is 4D Button (doc/Captured_Codes.md).
    unsigned char fifth[ 30 ];
    memset( fifth, 0, sizeof fifth );
    fifth[ 0 ] = 0x01;
    fifth[ 5 ] = 0x02;                                   // 4D Button
    CHECK( hid_dump_button_mask( fifth, 30 ) == (1ULL << 33) );
    CHECK( hid_dump_packet( fifth, 30, 100 ) == 1 );
    CHECK( hid_dump_packet( fifth, 30, 110 ) == 0 );

    fifth[ 5 ] = 0x01;                                   // Rotary8's touch
    CHECK( hid_dump_button_mask( fifth, 30 ) == (1ULL << 32) );

    // Every byte the payload carries is decoded...
    unsigned char all[ 30 ];
    memset( all, 0, sizeof all );
    for (int i = 1; i <= 5; i++) all[ i ] = 0xff;
    CHECK( hid_dump_button_mask( all, 30 ) == 0xffffffffffULL );

    // ...and a short report is not read past its end.
    CHECK( hid_dump_button_mask( all, 4 ) == 0x00ffffffULL );
    CHECK( hid_dump_button_mask( all, 0 ) == 0 );

    // The names as measured, including the 4D pair the table had swapped.
    CHECK( strcmp( get_button_name( 21 ), "4D Up" ) == 0 );
    CHECK( strcmp( get_button_name( 22 ), "4D Left" ) == 0 );
    CHECK( strcmp( get_button_name( 23 ), "4D Right" ) == 0 );
    CHECK( strcmp( get_button_name( 24 ), "4D Down" ) == 0 );
    CHECK( strcmp( get_button_name( 25 ), "Rotary1" ) == 0 );
    CHECK( strcmp( get_button_name( 32 ), "Rotary8" ) == 0 );
    CHECK( strcmp( get_button_name( 33 ), "4D Button" ) == 0 );

    printf( "hid_dump: %d checks passed\n", checks );
    return 0;
}
