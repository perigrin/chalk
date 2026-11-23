my @a=(1); my $f=sub { push @a,2 }; my $n=@a; $f->(); print "$n ".scalar(@a)."\n";
