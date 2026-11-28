my %h = (a=>[1,2]); my @c = @{$h{a}}; push @c, 3; my $r = $h{a}; push @$r, 4; print scalar(@{$h{a}}), "\n";
