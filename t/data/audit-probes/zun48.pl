my $v=eval { 5 } + eval { die "x\n"; 6 } // 0; print "$v\n";
