package A; sub m { my ($s,$p) = @_; $main::g = "w"; $p } package main; our $g = "o"; my $c = "A"; print $c->m($g), "\n";
