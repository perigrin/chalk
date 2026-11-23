my $i=0; my $f=sub { $i+=2 }; for (my $j=0; $j<3; $j++) { $f->() ; last if $i>3 } print "$i\n";
