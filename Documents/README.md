### RHex
Fly fishing related dynamic simulations.

Rich Miller,  19 February, 2019

The RHex project was created to make realistic dynamic computer simulations of interest to both fly fishers and fly rod builders.  It was preceded by the static Hexrod project of Wayne Cattanach, which was itself a computer updating in BASIC of the historical hand calculations of Garrison (see "A Master's Guide to Building a Bamboo Fly Rod", Everett Garrison and Hoagy B. Carmichael, first published in 1977).  Frank Stetzer translated Cattanach's code into CGI/Perl in 1997, and continues to maintain and upgrade it (www.hexrod.net).

In its current form, RHex is written in PERL with heavy use of PDL and comprises two main programs, RHexCast and RHexSwing3D.  These programs allow very detailed user specification of the components.  The first simulates a complete aerial fly cast in a vertical plane, following motion of the rod, line, leader, tippet and fly caused by a user-specified motion of the rod handle.  The second simulates, in full 3D, the motion of the line, leader, tippet and fly, both in moving water and in still air above, caused by a user-specified motion of the rod tip.  This simulation speaks to the common fishing technique of swinging streamers, but is also applicable to the drifting of nymphs.

Each program has a graphical interface that allows setting, saving, and retrieving of complex parameter sets, as well as running the simulations and saving the results, both as plots and as text.

