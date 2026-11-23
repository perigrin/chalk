my $x=0; my $f=sub { $x=1; 5 }; print "$x ", $f->(), " $x\n";
