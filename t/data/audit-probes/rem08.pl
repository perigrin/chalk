package C; sub new { bless [1,2], shift } sub sw { my $s=shift; @$s=reverse @$s } package main; my $o=C->new; $o->sw; print "@$o\n";
