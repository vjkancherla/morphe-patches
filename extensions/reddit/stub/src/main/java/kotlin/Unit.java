package kotlin;

/**
 * Stub of the real kotlin.Unit for extensions that must return the canonical
 * completed-coroutine value into the app: the app's dex exposes the instance as the
 * static field {@code a}, which is what compiled references must point at.
 */
public class Unit {
    public static final Unit a = new Unit();

    private Unit() {
    }
}
