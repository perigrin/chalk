package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return 5 }
package main; my $o = C->new; my $m = "inc"; my $r = $o->$m(); print "$r $o->{n}\n";
