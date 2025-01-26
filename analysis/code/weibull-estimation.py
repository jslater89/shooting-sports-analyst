import numpy as np
from scipy import stats

# Example usage:
if __name__ == "__main__":
    # Load your data here
    data = np.loadtxt("random-hfs.txt")  # Adjust path as needed
    
    # Optional: Compare with scipy's built-in estimator
    shape_scipy, loc, scale_scipy = stats.weibull_min.fit(data, floc=0)
    print(f"\nSciPy estimates:")
    print(f"Shape: {shape_scipy:.4f}")
    print(f"Scale: {scale_scipy:.4f}")
