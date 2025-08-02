#!./chalk

# ABOUTME: Perl compatibility test for conditional operators
# ABOUTME: Based on Perl's t/base/cond.t to ensure 100% compatibility

print "1..4\n";

$x = '0';

# Test cases adapted from Perl's t/base/cond.t
print $x eq $x; print "\n";  # Should print 1 (ok 1)
print $x ne $x; print "\n";  # Should print 0 (ok 2 if 0)  
print $x == $x; print "\n";  # Should print 1 (ok 3)
print $x != $x; print "\n";  # Should print 0 (ok 4 if 0)