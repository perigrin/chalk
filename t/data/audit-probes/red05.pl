use feature "try"; no warnings; my @l; for my $i (1..3) { try { die "a\n" if $i==2; push @l,$i } catch ($e) { push @l,"c"; next } push @l,"e" } print "@l\n";
