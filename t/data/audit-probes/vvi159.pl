our $s = "abc"; sub ed { chop $s; 1 } my @l = ($s, ed(), $s); print "@l\n";
