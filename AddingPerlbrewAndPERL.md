### AddingPerlbrew and PERL

Go online to https://perlbrew.pl/ and read about Perlbrew.
Then see if your machine has the `curl` executable.  It should be there since modern macs come with it installed.  Working in a Terminal window, at the prompt type:

`which curl`

The response should be something like `/usr/bin/curl`, which means `curl` was found, and you're ok.  Then to download and install the latest perlbrew, copy and paste the following line at the prompt:

`\curl -L https://install.perlbrew.pl | bash`

## Download the latest perlbrew

## Installing perlbrew
Using Perl </usr/bin/perl>
perlbrew is installed: ~/perl5/perlbrew/bin/perlbrew

perlbrew root (~/perl5/perlbrew) is initialized.

Append the following piece of code to the end of your ~/.bash_profile and start a
new shell, perlbrew should be up and fully functional from there:

    source ~/perl5/perlbrew/etc/bashrc

Simply run `perlbrew` for usage details.

Happy brewing!

\## Installing patchperl

\## Done.
Rich-Mac-mini-2016:~ rhexman$ 

Next, install the latest version of perl. At the terminal prompt copy and paste:
perlbrew install perl-5.28.1

Make sure to have the new perl be the active one:

`perlbrew switch perl-5.28.1`

Check:

`perlbrew info`

Finally get cpanm. Copy and paste:

`perlbrew install-cpanm`

Generally, for help with perlbrew, type

`perlbrew help`






















