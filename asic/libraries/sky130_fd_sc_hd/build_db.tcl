# Compile a SKY130 HD Liberty file into a Synopsys .db.
#
# Design Compiler cannot read Liberty directly, so every corner the DC flow uses
# has to be compiled once with Library Compiler. The Genus flow reads the same
# corners straight from .lib - this step exists only to keep DC on the identical
# corner rather than on whatever .db happened to be lying around.
#
# Usage (SKY130_LIBRARY_NAME defaults to the Liberty file's basename):
#   SKY130_LIBERTY=/path/to/x.lib SKY130_DB_OUTPUT=/path/to/x.db lc_shell -f build_db.tcl

set LIBERTY_FILE $env(SKY130_LIBERTY)
set DB_FILE $env(SKY130_DB_OUTPUT)
set DB_DIR [file dirname $DB_FILE]

if {[info exists env(SKY130_LIBRARY_NAME)] && $env(SKY130_LIBRARY_NAME) ne ""} {
    set LIBRARY_NAME $env(SKY130_LIBRARY_NAME)
} else {
    set LIBRARY_NAME [file rootname [file tail $LIBERTY_FILE]]
}

file mkdir $DB_DIR

if {![file exists $LIBERTY_FILE]} {
    puts stderr "ERROR: Liberty file does not exist: $LIBERTY_FILE"
    exit 1
}

puts "INFO: Reading Liberty file: $LIBERTY_FILE"
read_lib $LIBERTY_FILE

puts "INFO: Writing Synopsys database: $DB_FILE (library $LIBRARY_NAME)"
write_lib $LIBRARY_NAME -format db -output $DB_FILE

if {![file exists $DB_FILE]} {
    puts stderr "ERROR: failed to create .db: $DB_FILE"
    exit 1
}

puts "INFO: Generated .db: $DB_FILE"
exit
