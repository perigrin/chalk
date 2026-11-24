my $o={l=>[1,2]}; my $l=$o->{l}; $o->{l}=[9]; push @$l,3; print scalar(@$l), scalar(@{$o->{l}}), "\n";
