> 2023-06-15 This project will not be maintained because the unit I had was buggy (garbled OLED) and the replacement unit is buggy too so am going to buy a different brand. I do hope this project to be useful for anyone else so leaving the code up.


# Komplementary Kontrol #
_Unofficial Linux support for the Komplete Kontrol A-series keyboard by Native Instruments_
> I am in no way affiliated with Native Instruments 

## DISCLAIMER : USE THIS AT YOUR OWN RISK ##
I cannot be held responsible for any problems that might arise
from using these utilities.

Now that that is out of the way...

## About ##
This is a set of utilities to make the Komplete Kontrol A-series 
keyboards usable under Linux.

This has been developed using a A25 but I don't see any reason why 
this could not work for the other A-series keyboards.

It consists of two utilities:
- `komplement`
- `konfigure` 

The `komplement` tool is the thing that makes the non-MIDI buttons 
usable on your system. See below.

The `konfigure` tool generates SysEx packets that can be sent
to the device to configure the current preset (i.e. that maps the 
rotary dials to actual MIDI events). See below.

### Compiling and installing ###
The `konfigure` requires libasound2-dev, the `komplement` tool additionally
requires libhidapi-libusb0.

To install required libraries, run
    `apt install libhidapi-libusb0 libasound2-dev`

To compile the binaries, run 
    `make all`
    
If you want to install it on your system, run 
    `sudo make install`
    
> Note: Installation will also create the folders `/usr/share/komplementary-control/mappings` 
> and `/usr/share/komplementary-control/presets` where the mappings and presets are copied to.
> This is where the utilities will try to find the files if they do not exist in the path, so
> running `komplement -m rosegarden.map` will load it from 
> `/usr/share/komplementary-kontrol/mappings/rosegarden.map`.

### Compiling and installing on NixOS ###
A `flake.nix` is included, because NixOS has no `/usr/include` and no `/usr/lib` — the libraries and headers live inside hashed store paths. The Makefile therefore discovers ALSA and hidapi through `pkg-config` (falling back to the plain `-lasound` / `-lhidapi-libusb` names when there is no `.pc` file), and `MAPPINGS_PATH` / `PRESETS_PATH` are compiled pointing at the store path of the built package instead of `/usr/share`.

Build and install the package into the Nix store:
    `nix build`
    `./result/bin/komplement -h`

Get a development shell with gcc, make, pkg-config, ALSA and hidapi ready on `PKG_CONFIG_PATH`, then build the usual way:
    `nix develop`
    `make all`

> Note: flakes only see files that git tracks, so on a fresh clone add the flake to the index once: `git add flake.nix flake.lock`

The flake also exports a NixOS module that installs the binaries and the udev rules (the keyboard and `/dev/uinput` for the group named in `services.komplementary-kontrol.group`, `audio` by default):
```
{
  inputs.komplementary-kontrol.url = "github:<your-fork>/komplementary-kontrol";

  outputs = { nixpkgs, komplementary-kontrol, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        komplementary-kontrol.nixosModules.default
        {
          services.komplementary-kontrol.enable = true;
          users.users.<you>.extraGroups = [ "audio" ];
        }
      ];
    };
  };
}
```

> On NixOS `/etc/udev/rules.d` is a read-only symlink into the store, so
> `udev/55-komplete-kontrol.rules` cannot be copied there. Without the module,
> put the same lines into your own configuration; the module loads the `uinput`
> kernel module as well, because `/dev/uinput` does not exist without it:
> ```
> services.udev.extraRules = ''
>   SUBSYSTEM=="usb", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="1740", MODE="0660", GROUP="audio"
>   KERNEL=="hiddev*", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="1740", MODE="0660", GROUP="audio"
>   KERNEL=="uinput", MODE="0660", GROUP="audio", OPTIONS+="static_node=uinput"
> '';
> boot.kernelModules = [ "uinput" ];
> users.users.<you>.extraGroups = [ "audio" ];
> ```
> NixOS also ships `hardware.uinput.enable = true`, which loads the module and
> hands `/dev/uinput` to the group `uinput`; in that case either add your user
> to `uinput` as well, or set `services.komplementary-kontrol.group = "uinput"`
> so that a single group covers keyboard and `uinput` alike.

## komplement ##
This basically works by reading the relevant USB HID packets and 
mapping that to keys useful for your favourite software. 

This means that if your software is not the active window, any other 
active application will receive the keypresses. This is something 
to keep in mind.

Due to how it works, it needs to run while you want to use the keyboard 
in your DAW. 

If you are done using it, you can simply hit Ctrl+C to abort it and it shall
gracefully exit.

#### Permissions ####
This utility required read/write access to the USB device and only *write*
to `/dev/uinput` for sending keypresses.
> Note that it doesn't read from uinput, so your passwords are safe.

Access to these can be accomplished by either running the `komplement` binary 
as root, or allowing user access to the necessary files. 

Obviously, the latter is encouraged. (Running as root is bad, mkay.)

The `setfacl` utility can be used to allow write access to the `/dev/uinput` file. 
```
    $> sudo setfacl -m u:$USER:w /dev/uinput
```
> Note that changes with `setfacl` are not permanent and will need to be applied 
> again after a reboot.

For convenience, I have created the file `udev/55-komplete-kontrol.rules` that
can be used to set up USB device access for the group `audio` (chances are you 
have already added yourself to that group). If not, edit the rules file to 
a group you do belong to.

After copying that file (as root) to `/etc/udev/rules.d` and then running
    `sudo udevadm control --reload-rules`

You can unplug / plug the device so that permissions are set-up properly and 
then you no longer need to run the utility as root.


#### Mapping files ####
An example mapping is supplied in `mappings/rosegarden.map` that maps 
useful buttons to functionality in Rosegarden. This file can serve as a 
basis to create mappings for other software. 

A second example, `mappings/reaper.map`, maps the A-series buttons (and their
SHIFT variants) to stock REAPER shortcuts: transport, record, undo/redo, split,
marker insert, snapping/ripple/grid toggles, repeat, track navigation, mute,
media explorer, FX chain and zoom.

Check the file `doc/Supported_Keys.md` for a list of all the supported keys.

(If you do create your own, please share your mapping files so others 
can use it too!)


#### Examples ####
Example usage that loads the Rosegarden mapping and /dev/uinput for output:
```
$> ./komplement -m mappings/rosegarden.map -o /dev/uinput
```

(The above example assumes that the permissions are correctly set up.)

> Note on the USB IDs: the defaults are vendor `17cc`, product `1730`, which is
> what the A25 reports. Other models use a different product ID - a Komplete
> Kontrol A49 shows up as `17cc:1740` - so pass it on the command line:
> `./komplement -m mappings/reaper.map -p 1740`.
> `lsusb | grep -i 17cc` shows the IDs of your own keyboard.

#### Controls that are not handled yet ####
The buttons 1..39 of the payload are translated now, which covers the whole
A-series keyboard: the eight rotary encoders' touch sensors (bits 25..32), the
four 4D directions (bits 21..24), 4D Button (bit 33), and the rotation of the 4D
dial. The bit values were measured on an A49 and are tabulated in
`doc/Captured_Codes.md`.

What is still *not* translated is the rotation of the eight rotary knobs: it is
not in the HID report at all, the knobs send absolute Control Change messages
over MIDI instead (CC 14..21, channel 1, one controller per knob, 0..127, one
step per detent). Two ways to use them:

* let the DAW learn them: enable the keyboard as a MIDI input and MIDI-learn the
  parameter. Nothing to configure in `komplement`, but the parameter jumps to the
  knob's position, because the values are absolute;
* or teach `komplement` to read those CCs and translate them - not implemented.

The CC numbers come from the device's own configuration and `konfigure` can
change them (see below).

To look at what the device sends, run the tool with `-d`, which prints every HID
report that differs from the previous one, decoding the button mask, the 4D dial
and the names of the buttons that are set:

    ./komplement -m mappings/none.map -p 1740 -d

`tools/capture-a49.sh` does the same and captures the MIDI stream at the same
time, asking you to do one control at a time so that every packet can be
attributed:

    nix develop -c bash tools/capture-a49.sh 1740

## konfigure ##
This is a utility that creates a SysEx file that can be sent to the device
to configure it the rotary knobs.

#### Preset files ####
An example preset file is supplied in `presets/basic_cc.pst` that 
maps a few CC to the buttons.

#### Examples ####
Example that writes it to a separate file that you can then send
to the appropriate device with the `amidi` utility (`-q` keeps the verbose
report out of the SysEx file):
```
$> ./konfigure -q -p presets/basic_cc.pst > /tmp/sysex.syx
$> amidi -s /tmp/sysex.syx
```

It is also possible to send it directly to the device like so:
```
$> ./konfigure -p presets/basic_cc.pst -m "hw:3,0,0"
```
