use Class::Struct; struct(Pt => { x => '$', y => '$' }); my $p = Pt->new(x => 1, y => 2); $p->x(5); print $p->x, $p->y, "\n";
