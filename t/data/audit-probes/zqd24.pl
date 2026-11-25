sub inc { $_[0]++ } our $g=1; inc($g += 2); print "$g\n";
