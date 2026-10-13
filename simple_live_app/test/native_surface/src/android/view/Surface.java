package android.view;

public class Surface {
    private final String label;
    private boolean valid = true;
    private int releaseCount;

    public Surface(String label) {
        this.label = label;
    }

    public boolean isValid() {
        return valid;
    }

    public void setValid(boolean value) {
        valid = value;
    }

    public void release() {
        releaseCount++;
        valid = false;
    }

    public int releaseCount() {
        return releaseCount;
    }

    @Override
    public String toString() {
        return "Surface(" + label + ")";
    }
}
