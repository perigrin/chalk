# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a base class for YKid.
package YBase;
sub new { bless { v => 1 }, shift } sub hello { "hello " . $_[0]->name } sub name { "base" }
1;
