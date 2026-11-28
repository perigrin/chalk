our $s = "abc"; sub ed { $s x= 2; 1 } my @l = (length($s), ed(), length($s)); print "@l\n";
