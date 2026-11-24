my $x=1; my $f=sub { $x++ }; my $g=sub { $x*10 }; $f->(); print $g->(),"\n";
