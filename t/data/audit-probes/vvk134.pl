package C; sub new { bless {v => $_[1]}, $_[0] } sub get { $_[0]{v} } sub bump { $_[0]{v}++ } package main; my $o = C->new(1); my @l = ($o->get, $o->bump, $o->get); print "@l\n";
