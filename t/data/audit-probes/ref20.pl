my $x=1; my $f=sub { $x=2 }; if ($x==1) { $f->(); print "a$x\n" } print "b$x\n";
