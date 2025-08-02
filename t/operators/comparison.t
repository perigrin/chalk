#!./chalk

# ABOUTME: Test comparison operators (==, !=, <, >, <=, >=, eq, ne)
# ABOUTME: Validates type coercion and proper operator semantics

print "1..16\n";

# String comparison operators - eq and ne
$x = 'hello';
$y = 'hello';
$z = 'world';

print $x eq $y; print "\n";  # Should print 1
print $x ne $z; print "\n";  # Should print 1  
print $x eq $z; print "\n";  # Should print 0
print $x ne $y; print "\n";  # Should print 0

# Numeric comparison operators - == and !=
$a = '5';
$b = '5';
$c = '3';

print $a == $b; print "\n";  # Should print 1
print $a != $c; print "\n";  # Should print 1
print $a == $c; print "\n";  # Should print 0
print $a != $b; print "\n";  # Should print 0

# Numeric ordering operators - <, >, <=, >=
print $c < $a; print "\n";   # Should print 1 (3 < 5)
print $a > $c; print "\n";   # Should print 1 (5 > 3)
print $c <= $a; print "\n";  # Should print 1 (3 <= 5)
print $a >= $c; print "\n";  # Should print 1 (5 >= 3)

# Edge cases with numbers and strings
print '10' > '9'; print "\n";   # Should print 1 (numeric comparison)
print '10' gt '9'; print "\n";  # Should print 0 (string comparison, if gt implemented)
print '0' == ''; print "\n";    # Should print 1 (empty string is 0)
print '0' eq ''; print "\n";    # Should print 0 (different strings)