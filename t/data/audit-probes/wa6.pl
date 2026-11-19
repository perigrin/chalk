my @a = (1,2); my $f = sub { scalar @a }; @a = (1,2,3); print $f->(), "\n";
