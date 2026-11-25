# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose subs close over file lexicals its file-level code sets.
package YPriv;
my $priv = 5; my @pl = (1, 2); my %ph = (a => 1); my $cnt = 0;
sub priv { $priv } sub bump { ++$priv } sub pl { "@pl" } sub ph { $ph{a} } sub next_id { ++$cnt } sub addpl { push @pl, $_[0]; return }
1;
