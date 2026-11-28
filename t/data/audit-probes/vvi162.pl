our $s = "abc"; sub ed { $s++; 1 } my @l = ($s, ed(), $s); print "@l\n";
