use feature 'try'; no warnings; my @a=(1,2); try { for my $x (@a) { $x.="!"; die "x\n" } } catch ($e) { } print "@a\n";
