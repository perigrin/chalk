our $s = "abc"; sub ed { $s =~ s/b/z/; 1 } my @l = ($s, ed(), $s); print "@l\n";
