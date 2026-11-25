use Getopt::Long; local @ARGV = ("--name", "x", "--v", "rest"); my ($name, $v); GetOptions("name=s" => \$name, "v" => \$v); print "$name$v@ARGV\n";
