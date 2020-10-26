Globus Xfr Script for Batch and Files
===
```
Usage: gbxfr.sh [-hqvV] [-c <config_file>] -n xfr_label (...other required options...)

  Globus Xfr Script for Batch and Files

        --------------------------------------------------------------------
**NOTE: This script ONLY tested using BATCH mode! Other modes still pending.
            Patience is a virtue. ... and a word that begins with 'P'.
        --------------------------------------------------------------------

    -c configfile Path to config file, setting at least required variables.
                  (See template config file as example.)

  To override config file, or to run immediately:
    -n xfr_label  Transfer job name to show in task list

    -s source_ep  Source endpoint id  (required)
    -p file_path  Source file path  (required, must be abspath)
    -t target_ep  Target endpoint id  (required)
    -d dest_path  Destination path  (default '/~/')
    -B            Use basename of local file to place in dest_path.

    -b batch_file Path to batch file
                  Sets 'batch' transfer mode; note that -p and -d are
                  used to prepend to relative paths in batch_file.
    -o            Reuse/overwrite batch file using file_glob
    -f file_glob  Glob(s) of files to place into batch_file.
                  (default '*' within source '-p' file_path)
                  NOTE: Will create or OVERWRITE batch_file!

    -h         Display this help text and exit
    -q         Quiet
    -V         Display version information and exit
```
--

For Globus-specific [help][glb.help]

For Globus app [docs][glb.docs]

[glb.docs]:https://docs.globus.org/
[glb.help]:https://app.globus.org/help
