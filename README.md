# NSIS Java Locator

This NSIS plugin searches Windows for Java installations and reports back "the most suitable" installation found, if any. It is intended to be versatile letting you specify various options that will impact the search and what is deemed "the most suitable".

## Table of Contents
- [1. Operation](#1-operation)
  - [1.1 Windows registry search](#11-windows-registry-search)
  - [1.2 Environment variable search](#12-environment-variable-search)
  - [1.3 Windows `PATH` search](#13-windows-path-search)
  - [1.4 File path search](#14-file-path-search)
  - [1.5 File path filtering](#15-file-path-filtering)
  - [1.6 Exclusion](#16-exclusion)
  - [1.7 Sorting](#17-sorting)
  - [1.8 Returning the result](#18-returning-the-result)
- [2 Use](#2-use)
- [3 Parameters](#3-parameters)
  - [3.1 Valueless options](#31-valueless-options)
  - [3.2 Options with values](#32-options-with-values)
    - [3.2.1 Version expressions](#321-version-expressions)
    - [3.2.2 Log level](#322-log-level)
- [4 Building](#4-building)

## 1 Operation

The plugin performs the search in multiple steps, each of which can be influenced using options.

#### 1.1 Windows registry search

A set of predefined registry paths will be searched for both `HKEY_LOCAL_MACHINE` and `HKEY_CURRENT_USER` in both 32- and 64-bit "views":

* `SOFTWARE\JavaSoft`
* `SOFTWARE\Eclipse Adoptium`
* `SOFTWARE\Azul Systems\Zulu`
* `SOFTWARE\Azul Systems\Zulu 32-bit`
* `SOFTWARE\Semeru`
* `SOFTWARE\BellSoft\Liberica`

The plugin contains parsers that looks for the expected subkeys like for example `JRE\8.0.392.8\hotspot` or `Java Development Kit\1.8.0_392`. Additional registry paths can be searched by using the `/REGPATH` option or predefined paths can be excluded by using the `/DELREGPATH` option.

#### 1.2 Environment variable search

The predefined environment variable `%JAVA_HOME%` will be searched. Additional variables can be added using the `/ENVSTR` option and the predefined variable can be removed using `/DELENVSTR`. The parser will look for in the `bin` subfolder if the variable exist but doesn't include `bin`.

#### 1.3 Windows `PATH` search

The Windows `%PATH%` environmental variable will be searched so that any Java installations that have been added to `%PATH%` should be picked up. This search can be disabled using the `/SKIPOSPATH` option.

#### 1.4 File path search

Specified paths can be searched if specified as a parameter. Any parameter not belonging to a specific option is assumed to be a path to be searched. Specified paths can include "aliases" like `%ProgramFiles%` - which will be expanded automatically. There are no predefined file paths, so unless one or more is specified as parameters, none will be searched.

#### 1.5 File path filtering

Filtering paths can be applied across all installations already found in the previous steps. These will be excluded from the results. Filtering paths can include "aliases" which will be expanded before application. The following predefined filtering paths are default:

* `%commonprogramfiles%\Oracle\Java\javapath`
* `%commonprogramfiles(x86)%\Oracle\Java\javapath`
* `%commonprogramW6432%\Oracle\Java\javapath`
* `%ALLUSERSPROFILE%\Oracle\Java\javapath`
* `%SystemRoot%\system32`
* `%SystemRoot%\SysWOW64`

The `javaw.exe` found in the various "javapath" locations aren't real Java installations, they are merely "launchers" that tries to find a real installation using registry information. These are thus not wanted.

Additional filtering paths can be specified using the `/ADDFILTER` option, and existing filtering paths can be removed using `/DELFILTER`. Filtering paths must match the beginning of the Java installation paths that are to be filtered, which includes the drive letter. Drive letters should not be hard coded, so it's recommended to use aliases as in the predefined filtering paths. When expanded these will contain the correct drive letter for the system.

#### 1.6 Exclusion

Found Java installations can be excluded based on their version using the `/MINVER` and `/MAXVER` options. Any installations that doesn't meet the criteria will be removed from the list over found installations at this point.

#### 1.7 Sorting

If more than one Java installation remains at this point, the list will be sorted according to "suitability". This means that the highest version and build numbers will be preferred, 64-bit will be preferred over 32-bit and the option `/OPTVER` will be taken into account.

#### 1.8 Returning the result

After exclusion both by path filtering and version rules, and sorting, zero or more Java installations remain. If none are found or remain, an empty string is returned - otherwise the first in the list is deemed "the most suitable" and returned to the NSIS script by returning the full path to `javaw.exe`. Additional information can also be returned of any of the options `/RETVERSION`, `/RETBUILD`, `/RETVERSIONSTR`, `/RETINSTTYPE`, `/RETARCH` and `/RETARCHBITS` are specified. If no matching Java installation is found, all the additional options are also returned as empty strings so that the number of returned elements are consistent.

## 2 Use

NSIS Java Locator consists of four different DLL files, both 32- and 64-bit versions in both ANSI and "Unicode" (Widestring) versions. The version that corresponds to the NSIS variant in use must be used. Most will probably need the 32-bit "Unicode" version. Once the correct DLL has been selected, simply drop it in NSIS' `Plugins` folder and it is ready for use. The plugin only has one function, `Locate`, which can be called like this:

```nsi
NsJavaLocator::Locate [/OPTION] [VALUE] /END
```

Since the plugin doesn't take a fixed number of parameters and NSIS calls plugins in a very "crude" way (all parameters are simply pushed to the stack before the call), `/END` must _always_ be the last parameter - even if none others are specified. If `/END` is missing, your NSIS script will probably crash, as the plugin will keep draining the stack until it encounters `/END`.

When the plugin returns, the result of the search in the form of a string with the full path to `javaw.exe` or an empty string if none was found has been pushed to the stack. Use `Pop` to retrieve it. Unless one of the `/RET` options has been specified, only one value is pushed to the stack. For each `/RET` parameter specified, an additional value is pushed - even if the same `/RET` option is specified multiple times. The `/RET` values are pushed in the inverse of the specified order with the `javaw.exe` path pushed last, so that the values are pop'ed in the same order that they are specified.

## 3 Parameters

NSIS Java Locator can take any number of parameters. These consist of options, option and value pairs and the default: file paths to search. This means that any parameter that isn't an option and isn't a value following an option, is assumed to be a file path that is to be searched. All options start with a forward slash `/`. All parameters except the final `/END` are optional. Without any additional parameters, the Java search will executed with the default setting and the Java installation with the highest Java version will be returned.

#### 3.1 Valueless options

|<sub>Option</sub>|<sub>Description</sub>|
|--|--|
|<sub>`/SKIPOSPATH`</sub>|<sub>Makes the plugin skip searching the Windows PATH environment variable.</sub>|
|<sub>`/LOG`</sub>|<sub>Enables plugin logging to the installer's "details output" window. The log level determines what level of detail/what messages that are logged.</sub>|
|<sub>`/DIALOGDEBUG`</sub>|<sub>Only use this option for figuring out what's happening when the plugin is running. This will display a modal message box that will halt the plugin's execution for each logged message, and can be very obtrusive. The log level determines what level of detail/what messages that are shown.</sub>|
|<sub>`/RETVERSION`</sub>|<sub>Makes the plugin return the major version of the Java installation (e.g `7` or `21`) or an empty string if unknown.</sub>|
|<sub>`/RETBUILD`</sub>|<sub>Makes the plugin return the build of the Java installation (e.g `80` or `392`) or an empty string if unknown.</sub>|
|<sub>`/RETVERSIONSTR`</sub>|<sub>Makes the plugin return a string with the combination of version and build in the form `<Version>.<Build>` (e.g `8.392`) or an empty string if unknown.</sub>|
|<sub>`/RETINSTTYPE`</sub>|<sub>Makes the plugin return a string indicating the Java installation type, if known. Possible values are `JDK`, `JRE`, `Unknown` or an empty string if no installation was found.</sub>|
|<sub>`/RETARCH`</sub>|<sub>Makes the plugin return a string indicating the CPU architecture the Java installation is for. Possible values are `ia64`, `x64`, `x86`, `Unknown` or an empty string if no installation was found.</sub>|
|<sub>`/RETARCHBITS`</sub>|<sub>Makes the plugin return only the number of bits of the CPU architecture the Java installation is for. Possible values are `32`, `64` or an empty string if unknown.</sub>|

#### 3.2 Options with values

|<sub>Option</sub>|<sub>Type</sub>|<sub>Description</sub>|
|--|:--:|--|
|<sub>`/REGPATH`</sub>|<sub>String</sub>|<sub>Adds a registry path to search. Registry paths should use backslashes (`\`) between key names, and should start after where `HKEY_LOCAL_MACHINE` or `HKEY_CURRENT_USER` would be. Every registry path will be searched with both prefixes.</sub>|
|<sub>`/DELREGPATH`</sub>|<sub>String</sub>|<sub>Removes a registry path from the search. This is useful to remove [predefined registry paths](#11-windows-registry-search). The path must be an exact match.|
|<sub>`/ENVSTR`</sub>|<sub>String</sub>|<sub>Adds an environmental variable to the search. The string must contain an environmental variable enclosed in `%` like this: `%JAVA_HOME%`. `%JAVA_HOME%` is predefined and doesn't need to be added. If the string doesn't "expand" when passed to the Windows API, it isn't added to the search. This means that any variable specified will only be "used" on systems where they are defined.</sub>|
|<sub>`/DELENVSTR`</sub>|<sub>String</sub>|<sub>Removes an environmental variable from the search. This is useful to remove the predefined `%JAVA_HOME%` variable from the search.</sub>|
|<sub>`/ADDFILTER`</sub>|<sub>String</sub>|<sub>Adds a filtering path. See [1.5 File path filtering](#15-file-path-filtering) for further information.</sub>|
|<sub>`/DELFILTER`</sub>|<sub>String</sub>|<sub>Removes a filtering path. This is useful to remove [predefined filtering paths](#15-file-path-filtering) The filtering path much be an exact match.</sub>|
|<sub>`/MINVER`</sub>|<sub>[Version expression](#321-version-expressions)</sub>|<sub>Specifies the minimum Java version to include in the search.</sub>|
|<sub>`/MAXVER`</sub>|<sub>[Version expression](#321-version-expressions)</sub>|<sub>Specifies the maximum Java version to include in the search.</sub>|
|<sub>`/OPTVER`</sub>|<sub>[Version expression](#321-version-expressions)</sub>|<sub>Specifies the "optimal" Java version. Java installations that match this will be preferred when selecting "the most suitable" installation.</sub>|
|<sub>`/LOGLEVEL`</sub>|<sub>[Log level](#322-log-level)</sub>|<sub>The log level for the plugin if either `/LOG` or `/DIALOGDEBUG` is specified.</sub>|

##### 3.2.1 Version expressions

Version expressions can be used to specify a specific version, with or without build, or any versions "less than" or "greater than" a given version. The syntax is:
```
[ < | <= | = | >= | > ] <Version> [.<Build>]
```
If no operator is specified, the operator is context based: For minimum, greater than is assumed. For maximum, less than is assumed. For optimal, equals is assumed.

If the operator is equals and the build isn't specified, any build of the specified version will match. If both version and and build are specified, both must match.

If the operator is less than or greater than, with or without equals, it will be evaluated slightly differently if build is specified than if it is not. For example, `<9` will match any Java version that is 8 or less, regardless of build - but no Java 9 version will match. `<=9.20` on the other hand will also match Java 9 up to and including build 20. 

##### 3.2.2 Log level

The log level determines what messages will be logged or shown if `/LOG` or `/DIALOGDEBUG` is specified. The allowed values are:

* `ERROR`
* `WARN`
* `INFO`
* `DEBUG`

The default log level is `INFO`.

## 4 Building

NSIS Java Locator has been made using Lazarus 2.2.6 with Free Pascal 3.2.2. The 32-bit version of Lazarus with 64-bit cross-compilation was used to be able to compile both 32- and 64-bit DLLs. 

It is probably possible to build NSIS Java Locator using Free Pascal alone, but it would require some manual configuration of build paths and options. By opening `NsJavaLocator.lpi` with Lazarus, everything should be ready to compile without further configuration. All project paths are relative.