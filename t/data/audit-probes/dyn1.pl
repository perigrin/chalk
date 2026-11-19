package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return }
package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";
