package P; sub new { bless {v=>$_[1]}, $_[0] } sub cmp { $_[0]{v} <=> $_[1]{v} } package main; my @o = map { P->new($_) } 3,1,2; print join(",", map { $_->{v} } sort { $a->cmp($b) } @o), "\n";
