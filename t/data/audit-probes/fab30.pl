my @d=(4,0,2); my $s=0; for (@d) { $s += eval { 8/$_ } // 100 } print "$s\n";
