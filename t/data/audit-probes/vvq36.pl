my %h = (k=>1); my $r = \%h; sub c { $h{k} = 9; 0 } my $s = $r->{k} . c(); print "$s\n";
