my $r = \my @a; push @$r, 1, 2; my $h = \my %h; $h->{k} = 1; my $s = \my $v; $$s = 5; print "@a$h{k}$v\n";
