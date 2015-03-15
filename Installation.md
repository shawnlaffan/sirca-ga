This page needs to be completed.

Star the page if you wish to be notified when the page is modified.  This is done by clicking on the star next to the page title text.

# Introduction #

This system is only set up for a source code install.  You will need to use a subversion client to download the software.
Instructions for obtaining the code are at http://code.google.com/p/sirca-ga/source/checkout (for Windows I use [TortoiseSVN](http://tortoisesvn.net/downloads)).

Once that is done you will need to install any dependencies.  The best way is to install the BiodiverseNoGUI bundle.

  * If you are using a perl that supports the PPM client (e.g. ActivePerl) then use:
```
ppm install Bundle-BiodiverseNoGUI
```

  * Otherwise use the CPAN shell:
```
perl -MCPAN -e "install Bundle::BiodiverseNoGUI"
```

  * If, when running the Sirca model, Perl complains that it cannot locate a file then this library will need to be installed using the CPAN or PPM methods.  The complaint will contain text like `Can't locate Fred/Fred.pm in @INC (@INC contains:...)`  In this case, install package Fred-Fred (substitute a hyphen for each forward slash "/", and remove the trailing ".pm" from the module it cannot locate). This can happen if one or more of the modules listed in the bundle failed to install.

# GUI #

The GUI requires a number of additional libraries.  See the list at http://code.google.com/p/sirca-ga/source/browse/trunk/etc/py_mods.txt
Even then we don't guarantee it will work.  It needs some attention...