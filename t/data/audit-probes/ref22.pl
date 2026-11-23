my $i=0; my $f=sub { $i++ }; while ($i<3) { $f->() } print "$i\n";
