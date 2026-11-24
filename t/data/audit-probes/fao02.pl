package P; sub new { my ($c,%a)=@_; bless {%a}, $c } sub x { $_[0]{x} } sub setx { $_[0]{x}=$_[1] } package main; my $a=P->new(x=>1); my $b=$a; $b->setx(7); print $a->x,"\n";
