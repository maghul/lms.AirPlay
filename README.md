AirPlay plugin
-----------------------------------------------------
This is a Logitech Media Server plugin that makes the Squeezebox
players capable of acting as AirPlay players. Metadata, including
coverart, and volume control can be handled from the the AirPlay source.

The Squeezebozes will also be able to control the
connected AirPlay source by issuing stop, play, forward
and backward.

Volume control can be issued from the AirPlay source
but if the squeezebox uses relative volume that is only
up or down volume (i.e. when an amplifier is controlled
using the IR blaster) Then the iDevice volume control will
be at center position, that is display a volume of 50. 
When the volume control is dragged up the volume
on the speaker will be increased and when the volume is
dragged down the volume will be decreased. When the volume
control is released it will return to the center position.

Dependencies
------------
github.com/maghul/go.squareplay

License
-------
The AirPlay package is licensed under the LGPL with an exception that allows it to be linked statically. Please see the LICENSE file for details.

Useage
------
It should be installed to an LMS Plugin directory. It does not
contains the airport.key but will search for it and store it
as needed.
