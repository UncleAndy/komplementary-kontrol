#include "hid_dump.h"
#include "button_names.h"

// The previous report, so that unchanged ones stay silent.
static unsigned char previous_packet[ HID_DUMP_PACKET_SZ ];
static int previous_length = 0;
static int have_previous = 0;
static int dump_count = 0;

unsigned long long hid_dump_button_mask( const unsigned char * packet, int length )
{
    unsigned long long mask = 0;

    // Bytes 1..5 carry buttons 0..39, one byte per group of eight.
    for (int i = 1; i <= 5 && i < length; i++)
        mask |= ((unsigned long long)packet[ i ]) << ((i - 1) * 8);

    return mask;
}

int hid_dump_packet( const unsigned char * packet, int length, long long stamp_ms )
{
    if (length < 0) length = 0;
    if (length > HID_DUMP_PACKET_SZ) length = HID_DUMP_PACKET_SZ;

    int differs = (!have_previous || length != previous_length) ? 1 : 0;
    if (!differs && memcmp( previous_packet, packet, (size_t)length ) != 0) differs = 1;

    if (!differs) return 0;

    dump_count++;

    printf( "[dump #%d @%lldms] len=%d :", dump_count, stamp_ms, length );
    for (int i = 0; i < length; i++) printf( " %02x", packet[ i ] );
    printf( "\n" );

    if (have_previous)
    {
        printf( "[dump #%d] changed:", dump_count );
        if (length != previous_length) printf( " len %d->%d", previous_length, length );

        const int common = length < previous_length ? length : previous_length;
        for (int i = 0; i < common; i++)
        {
            if (previous_packet[ i ] != packet[ i ])
                printf( " [%d] %02x->%02x", i, previous_packet[ i ], packet[ i ] );
        }
        printf( "\n" );
    }

    // Decode what the protocol is already known to use, so the log can be read
    // without counting hex offsets by hand. Everything else in the packet is
    // simply shown as bytes above - that is the point of the dump.
    const unsigned long long mask = hid_dump_button_mask( packet, length );

    printf( "[dump #%d] mask=0x%010llx (bit0=SHIFT)", dump_count, mask );
    if (length > 28) printf( " dial[28]=0x%02x", packet[ 28 ] );
    printf( "\n" );

    // And the names, so that a capture can be read without the bit table at
    // hand. Note that the rotary knobs' rotation is *not* in this report: they
    // report it over MIDI (CC 14..21), only their touch sensors show up here.
    printf( "[dump #%d] buttons:", dump_count );
    {
        int any = 0;
        for (int b = 0; b < TOGGLE_BUTTON_TOTAL; b++)
        {
            if (mask & (1ULL << b))
            {
                printf( " %s", get_button_name( b ) );
                any = 1;
            }
        }
        if (!any) printf( " none" );
    }
    printf( "\n" );

    fflush( stdout );

    memcpy( previous_packet, packet, (size_t)length );
    previous_length = length;
    have_previous = 1;

    return 1;
}
