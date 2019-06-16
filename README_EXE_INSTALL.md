### RHex-0.1.0

If you found this README_EXE_INSTALL you have already unzipped the distribution.  

### Instructions for finishing the installation of the executable version of RHex for the Mac

In the same folder as this file there is also a file named RHex_INSTALL.sh.  Simply double click on it. A Mac Terminal window will open and three new files, RHexSwing3D, RHexCast3D, and RHexReplot3D will be created. When you see the line: `[Process completed]` you can close the window.  The three new files are the RHex executables. (Actually they are  aliases to the file rhexexe, so they do not use up any more memory on your machine, but they behave like independent applications.)

On the Mac, RHex needs to have XQuartz installed to provide windows for the drawings. If it is not yet on your machine, go to https://www.xquartz.org/ and hit the download link. Simple dialogs will lead you through the installation process.  Note especially that you need to log out and then log back in to complete the installation.

Once XQuartz is in place, you can double click on the executables to start them running.

### Instructions for finishing the installation for Windows

In the same folder as this README there is also a file named RHex_INSTALL.cmd.  Double clicking on it will open a Command Prompt window and create three new files, RHexSwing3D.exe, RHexCast3D.exe, and RHexReplot3D.exe. When this has been done, the window will disappear.  The three new files are the RHex executables. (Actually they are hard links to the file rhex.exe, so they do not use up any more memory on your machine, but they behave like separate executables.)

In Windows, RHex uses the native windowing, so there is nothing more to be done there.  However, RHex also needs an installed copy of Gnuplot to create the drawings.  If you have not previously installed Gnuplot, go to https://sourceforge.net/projects/gnuplot/files/gnuplot/5.2.6/ and hit the green “Download Latest Version” button. This will put a copy of the self-install executable (gp526-win64-mingw_2.exe) in your downloads folder (or wherever your downloads usually go).  Double click on it to launch the installer.  You will be shown a number of dialogs and asked several questions.  Agree to everything.  When you hit the Finish button at the end of the process, a whole gnuplot directory will have been installed in the directory C:\Program Files\ which is where Windows keeps many of its executables.

According to the gnuplot documentation, you should now be ready to go.  You can try double clicking RHexReplot3D.exe.  If it works, fine.  if not, it will be because the installer did not succeed in adding the directory containing gnuplot.exe to the system path that windows uses to search for executables to run.  You will have to append the path yourself, adding exactly the text `C:\Program Files\gnuplot\bin`.  Windows has made this very easy to do.  The link https://www.howtogeek.com/118594/how-to-edit-your-system-path-for-easy-command-line-access/ leads you through the steps, pictorially, and in complete detail.

Double click on the executables to start them running.

### More information

At this point you should read the first part of the README.md file also included in the unzipped folder, which is a more complete introduction to RHex. Also read the last section of README.md to learn about controlling the active output plots.
