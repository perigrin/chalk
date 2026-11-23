my $s="a"; my $f=sub { $s.="b"; $s }; my $t = $s . $f->() . $s; print "$t\n";
