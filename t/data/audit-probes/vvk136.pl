package C; sub new { bless {v => $_[1]}, $_[0] } sub bump { $_[0]{v}++; 0 } package main; my $o = C->new(1); my @l = ($o->{v}, $o->bump, $o->{v}); print "@l\n";
