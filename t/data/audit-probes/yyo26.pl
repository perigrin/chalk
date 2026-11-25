use Storable qw(dclone); my $d = { a => [1,2] }; my $c = dclone($d); push @{$c->{a}}, 3; print scalar(@{$d->{a}}), scalar(@{$c->{a}}), "\n";
