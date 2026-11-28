package C; sub new { bless {v => $_[1]}, $_[0] } sub cmp2 { $_[0]{v} <=> $_[1]{v} } package main; my @o = sort { $a->cmp2($b) } map { C->new($_) } 3, 1, 2; print join("", map { $_->{v} } @o), "\n";
