### ParameterList_Swing

#### FLY LINE:

**totalLength** - The combined length in feet of the part of the fly line outside the tip guide, the leader, and the tippet.  It must be positive. Typical range is [10,50].

**nominalWeight** - Fly line nominal weight in grains per foot. For tapered lines, this is supposed to be the average grains per foot of the first 30 feet of line.  Must be non-negative. The typical range [1,15].  About 15 grains make one gram, and 437.5 grains make one ounce.
    
**estimatedDensity** - Fly line density. Non-dimensional.  Used for computing diameters when only weights per foot are known.  Must be positive.  Typical range is [0.5,1.5].  Densities less than 1 float in fresh water, greater than 1 sink.

**nominalDiameter** - In inches.  Used only for level lines.  Must be non-negative. Typical range is [0.030,0.090].

**coreDiameter** - The braided or twisted core of a coated fly line provides most of the tensile strength and elastic modulus.  The diameter in inches.  Must be non-negative.  Typical range is [0.010,0.050].
    
**coreElasticModulus** - Also known as Young\'s Modulus, in pounds per square inch.  Dependent on the type of material that makes up the core.  Must be non-negative.  Typical range is [1e5,4e5], that is, [100,000** - 400,000].
    
**dampingModulus** - In pounds per square inch.  Dependent on the material type.  Must be non-negative.	A hard number to come by in the literature.  However, it is very important for the stability of the numerical calculation.  Values much different from 1 slow the solver down a great deal, while those much above 10 lead to anomalies during stripping.


#### LEADER:
    
**length** - In feet. Must be non-negative.  Typical range is [5,15].

**weight** - In grains per foot.  Used only for level leaders.  Weight must be non-negative. Typical range for sink tips is [7,18].

**diameter** - In inches.  Used only for level leaders.  Must be positive. Typical range is	[0.004,0.050], with sink tips in the range [0.020,0.050].


#### TIPPET (always level):

**length** - In feet. Must be non-negative. Typical range is [2,12].

**diameter** - In inches.  Must be non-negative. Typical range is [0.004,0.012]. Subtract a tippet X value from 0.011 inches to convert X\'s to inches.


#### FLY:

**weight** - In grains. Must be non-negative.  Typical range is [0,15], but a very heavy intruder might be as much as 70.

**nominalDiameter** - In inches.  To account for the drag on a fly, we estimate an effective drag diameter and effective drag length.  Nominal diameter must be non-negative. Typical range is [0.1,0.25].

**nominalLength** - In inches.  Must be non-negative. Typical range is [0.25,1].

**estimatedDisplacement** - In cubic inches.  To account for buoyancy, we need to estimate the actual volume displaced by the fly materials.  This is typically very much less than the drag volume computed from the drag diameter and length described above.  Fly nom volume must be non-negative. On small flies this may be just a little more than the volume of the hook metal.  Typical range is [0,0.005].


#### AMBIENT

**gravity** - Gravity in G's, must be must be non-negative. Typical value is 1.

**dragSpecsNormal** - Three comma separated numbers that, together with the relative fluid velocity determine the drag of a fluid perpendicular to a nominally straight line segment.  The specs must be a string of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.  Remarkably, these numbers do not much depend on the type of fluid (in our case, air or water).  Experimentally measured values are 11,-0.74,1.2, and you should only change them with considerable circumspection.

**dragSpecsAxial** -  Again three comma separated numbers.  Analogous to the normal specs described above, but accounting for drag forces parallel to the orientation of a line segment. The theoretical support for this drag model is much less convincing than in the normal case.  You can try 11,-0.74,0.1.  The last value should be much less than the equivalent value in the normal spec, but what its actual value should be is not that clear.  However, the situation is largely saved by that fact that whatever the correct axial drag is, it is always a much smaller number than the normal drag, and so should not cause major errors in the simulations.


#### STREAM

**surfaceVelocity** - Water surface velocity in feet per second at the center of the stream.  Must be non-negative. Typical range is [1,7], a slow amble to a very fast walk.

**surfaceLayerThickness** - Water surface layer thickness in inches.  Mostly helpful to the integrator because it smooths out the otherwise sharp velocity break between the (assumed) still air and the flowing water.  Must be must be non-negative. Typical range is [0.1,2].

**bottomDepth** - Bottom depth in feet.  In our model, the entire stream is uniformly deep, and the flow is always parallel to the X-axis, which points downstream along the stream centerline.  Must be must be non-negative.  Frictional effects of the bottom on the water are important, especially under the good assumption of an exponential profile of velocity with depth.  See below. Typical range is [3,15].

**halfVelocityThickness** - In feet.  Only applicable to the case of exponetial velocity variation with depth.  Half thickness must be positive, and no greater than half the water depth. Typical range is [0.2,3].  A small half-thickness means a thinner boundary layer at the stream bottom.

**horizontalHalfWidth** - The cross-stream distance in feet from the stream centerline to the point where, at any fixed depth, the downstream velocity is half of its value at that depth at the stream centerline.  Must be positive. Typical range is [3,20].

**horizontalExponent** - Sets the relative square-ness of the cross-stream velocity profile.  Must be either 0 or greater than or equal to 2.  Zero means no cross-stream variation in velocity.  Larger values give less rounded, more square cross-stream profiles. Typical range is 0 or [2,10].

**showVelocityProfile** - If non-zero (say, 1), a graph of the vertical velocity profile is drawn before the calculation begins.  If 0, this plot is not drawn.  Draw the profile to get a feeling for the effect of varying half-velocity thicknesses.  If the cross-stream profile is not constant, and this parameter is not 0, a second plot showing the cross-stream drop-off will also be drawn.



#### INITIAL LINE CONFIGURATION

**rodTipToFlyAngle** - Sets the cross-stream angle in degrees at the start of the integration.  Must be in the range (-180,180).  Zero is straight downstream, 90 is straight across toward river left, -90 is straight across toward river right, and 180 is straight upstream.


**lineCurvature** - In units of 1\/feet. Equals 1 divided by the radius of curvature.  With the direction from the rod tip to the fly set as above, non-zero line curvature sets the line to bow along a horizontal circular arc, either convex downstream (positive curvature) or convex upstream (negative curvature).  The absolute value of the curvature must be no greater than 2\/totalLength.  Initial curvature corresponds to the situation where a mend was thrown into the line before any significant drift has occurred.

**preStretchMultiplier** - Values greater than 1 cause the integration to start with some amount of stretch in the line.  Values less than 1 start with some slack.  This parameter was originally inserted to help the integrator get started, but doesn't seem to have an important effect.  Must be no less than 0.9. Typical range is [1,1.1].

**tuckHeight** - Height in feet above the water surface of the fly during a simulated tuck cast.  Must be non-negative. Typical range is [0,10].

**tuckVelocity** - Initial downward velocity of the fly in feet per second at the start of a simulated tuck cast.  Must be non-negative. Typical range is [0,10].



#### LINE MANIPULATION AND ROD TIP MOTION

**laydownInterval** - In seconds.  Currently unimplemented.  The time interval during which the rod tip is moved down from its initial height to the water surface.  Must be non-negative. Typical range is [0,1].

**sinkInterval** - In seconds.  Only applicable when stripping is turned on.  This is the interval after the start of integration during which the fly is allowed to sink before stripping starts.  Must be must be non-negative. Typical range is [0,35], with the longer intervals allowing a full swing before stripping in the near-side soft water.

**stripRate** - In feet per second.  Once stripping starts, only constant strip speed is implemented.  Strip rate must be must be non-negative. Typical range is [0,5].  Zero means no stripping.

**rodTipStartCoords** - In feet.  Sets the initial position of the rod tip.  Must be of the form of three comma separated numbers, X,Y,Z. Typical horizontal values are less than an arm plus rod length plus active line length, while typical vertical values are less than an arm plus rod length.

**rodTipEndCoords** - Same form and restrictions as for the start coordinates.

If the start and end coordinates are the same, there is no motion.  This is one way to turn off motion.  The other way is to make the motion start and end times equal (see below).

**rodPivotCoords** - Same form as the start coordinates.  These coordinates are irrelevant if the rod tip track is set as a straight line between its start and end.  However if the tip track is curved (see below), the pivot, which you may envision as your shoulder joint, together with the track starting and ending points defines a plane.  In the current implementation, the curved track is constrained to lie in that plane.  Typically the distance between the pivot and the start and between the pivot and the end of the rod tip track is less than the rod plus arm length.  The typical pivot Z is about 5 feet.

**trackCurvature** - In units of 1\/feet. Equals 1 divided by track the radius of curvature. Sets the amount of bow in the rod tip track.  Must have absolute value less than 2 divided by the distance between the track start and the track end.  Positive curvature is away from the pivot, negative curvature, toward it.

**trackSkewness** - Non-zero values skew the curve of the track toward or away from the starting location, allowing tracks that are not segments of a circle.  Positive values have peak curvature later in the motion.  Typical range is [-0.25,0.25].

**motionStart and End times** - In seconds.  If the end time is earlier or the same as the start time, there is no motion.

**motionVelocitySkewness** - Non-zero causes the velocity of the rod tip motion to vary in time.  Positive cause velocity to peak later.  Typical range is [-0.25,0.25].

**showTrackPlot** - Non-zero causes the drawing, before the integration starts, of a rotatable 3D plot showing the rod tip track.  You can see the same information at the end of the integration by looking at the rod tip positions in the full plot, but it is sometimes helpful to see an  early, uncluttered version.


#### INTEGRATION, PLOTTING AND SAVING

**numberOfSegments** - The number of straight segments into which the line is divided for the purpose of calculation.  The integrator follows the time evolution of the junctions of these segments.  Must be an integer >= 1.  Larger numbers of segments mean a smoother depiction of the line motion, but come at the cost of longer calculation times.  These times vary with the 3rd power of the number of segments, so, for example, 20 segments will take roughly 64 times as long to compute as 5 segments. Typical range is [5,20].  It is often a good strategy to test various parameter setups with 5 segments, and when you have approximately what you want, go to 15 or even 20 for the final picture.

**segmentsExponent** - Values different from 1 cause the lengths of the segments to vary as you go from the rod tip toward the fly.  The exponent must be positive.  Values less than 1 make the segments near the rod tip longer than those near the fly.  This is usually what you want, since varying the lengths but not the number does not change computational cost (that is, time), and it is generally desirable to have more detail in the leader and tippet than in the fly line proper.  Typical range is [0.5,2].

**t0** - The notional time in seconds when the compution begins.  Must be non-negative, but this entails no loss of generality. Usually set to 0.

**t1** - The notional time when the computation ends.  Must larger than t0. Usually less than 60 seconds.

**dt0** - The initial computational timestep.  Must be positive.  Since the integrator has the ability to adjust the timestep as it goes along, this setting is not very important.  However, finding an appropriate value saves some computation time as the integrator begins its work. Typical range is [1e-4,1e-7].

**plotDt** - In seconds. This is an important parameter in terms of the utility of the final 3D plots. It sets the (uniform) interval at which a sequence of segment junction coordinates are reported by the integrator.  The integrator guarantees that the reported position values at these times have the desired degree of accuracy.  Must be positive.  There is a modest computational cost for more frequent reporting, but it is not great.  The bigger problem is that a short plotDt interval clutters up the final 3D graphic.  For the purpose of understanding the details of a swing, an interval of 1 second is usually a good choice, since adjacent traces are far enough apart that they don\'t obscure one another, and also since counting traces is then the same as counting seconds.  However, sometimes you want to see more detail, and have reporting occur earlier.  This happens mainly if for some reason the calculation has trouble getting started, and you want to catch the integrator\'s earliest efforts. Typical range is [0.1,1].

Note, however, that if you have a plot that is too cluttered, you can use the save results button (in particular, the save as text option).  This writes the results to a file.  Later you can run the RHexReplot3D program to read this file, and replot it in less dense and more restricted time manner.  Of course, replot can only work with what you have given it, so if the initially reported data is too sparse, you are stuck.

**plotZScale** - Allows for changing the magnification of the plotted Z-axis relative to the plotted X- and Y-axes.  Magnification must be no less than 1. Typical range is [1,5].  This magnification only affects display, not the underlying computed data.  The replot program allows redisplay at a different vertical magnification.

**integrationStepperChoice** - This menu allows you to choose from among 11 different stepper algorithms.  Some work better (are faster and more reliable) in some situations, and others work better in other situations.  However, for our purposes, the first choice, msbdf_j, seems to give the best results.

**saveOptions** - When you hit the Save Out button if the \"plot\" box is checked (colored red), an .eps picture file of the results will be created and saved.  This picture can be attached to an email or viewed in any of a number of programs.  In particular, on the mac, it can be opened in Preview.  However, this picture is \"static\".  What you see is what you get.  You can only resize it.  This is unlike the \"live\" plot that is shown when a RHexSwing3D run is paused or completes, which can be rotated any which way using the mouse.  On the other hand, if you check the \"data\" box, a text file is created.  That file can be opened in any text editor, and you can read the actual coordinate numbers that define the traces, as well as the parameter settings that gave rise to those traces.  In addition, that file can be opened in RHexReplot3D, and from there replotted in live, rotatable form.

**verbose** - Allows you to specify the amount of textual information that is displayed during an integrator run.  You can set the value to any of the integers in the range 0 to 3 inclusive.  The higher the number, the more information displayed.  Numbers less than or equal to 2 are essentially cost free, and setting verbose to 2 is generally the best choice, since it gives you a satisfying graphic depiction of the progress of the calculation.  This, among other things, lets you chose opportune moments to pause the run and view a plot of the swing up to that time.  Verbose set to 0 prints only the most general indication that the program is running or stopped, as well as actual error messages that mean that the calculation cannot start or proceed for some reason, typically because you have used unallowed parameter values, but also sometime because there is a programming bug that needs to be corrected.  Verbose set to 1 additionally prints warnings about typical ranges of parameters.  Verbose set to 2 prints all these things, plus indicating progress through the run setup procedure, plus the progress graphic and a few more details about computation times and the like.  On interesting special feature, is that if you have a level leader, its still water sink rate is computed.  It is often of interest to compare this number to the manufacturer\'s advertised value.  For verbose less than or equal to 2, all the output appears in the status pane on the control panel.  There is a scroll bar on the right hand edge of the pane that lets you look back at text that passed by earlier.

Verbose equal to 3 is an entirely different animal.  It generates a lot more output, which includes, at each integrator test step, a listing of all the forces exerted on the segment centers of gravity, including gravitation, buoyancy, and fluid drag, as well as the tension and dissipative forces acting along the segments.  All these forces balance against inertial forces due to the segment masses to determine the dynamics of the swing.  Printing all this slows down the calculation quite a bit, but can be fascinating to look at, especially if something counter intuitive is happening.  To accomodate all this output, the program is set up print it in the much larger Terminal application window that is automatically created when RHexSwing3D is launched.  In addition to capacity, the terminal window has two very important other advantages:  it is searchable with the standard mac mechanisms, and is savable to a file, so you can keep the run details for as long as you want.

