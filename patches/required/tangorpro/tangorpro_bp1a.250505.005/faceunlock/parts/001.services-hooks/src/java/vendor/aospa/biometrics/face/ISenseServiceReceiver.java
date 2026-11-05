/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/tools/android-15/aidl --lang=java -I/tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/src/ParanoidSense/interfaces/biometrics/face/aidl/src -o gen /tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/src/ParanoidSense/interfaces/biometrics/face/aidl/src/vendor/aospa/biometrics/face/ISenseServiceReceiver.aidl
 */
package vendor.aospa.biometrics.face;
/** @hide */
public interface ISenseServiceReceiver extends android.os.IInterface
{
  /** Default implementation for ISenseServiceReceiver. */
  public static class Default implements vendor.aospa.biometrics.face.ISenseServiceReceiver
  {
    @Override public void onEnrollResult(int faceId, int userId, int remaining) throws android.os.RemoteException
    {
    }
    @Override public void onAuthenticated(int faceId, int userId, byte[] token) throws android.os.RemoteException
    {
    }
    @Override public void onAcquired(int userId, int acquiredInfo, int vendorCode) throws android.os.RemoteException
    {
    }
    @Override public void onError(int error, int vendorCode) throws android.os.RemoteException
    {
    }
    @Override public void onRemoved(int[] faceIds, int userId) throws android.os.RemoteException
    {
    }
    @Override public void onEnumerate(int[] faceIds, int userId) throws android.os.RemoteException
    {
    }
    @Override public void onLockoutChanged(long duration) throws android.os.RemoteException
    {
    }
    @Override
    public android.os.IBinder asBinder() {
      return null;
    }
  }
  /** Local-side IPC implementation stub class. */
  public static abstract class Stub extends android.os.Binder implements vendor.aospa.biometrics.face.ISenseServiceReceiver
  {
    /** Construct the stub at attach it to the interface. */
    @SuppressWarnings("this-escape")
    public Stub()
    {
      this.attachInterface(this, DESCRIPTOR);
    }
    /**
     * Cast an IBinder object into an vendor.aospa.biometrics.face.ISenseServiceReceiver interface,
     * generating a proxy if needed.
     */
    public static vendor.aospa.biometrics.face.ISenseServiceReceiver asInterface(android.os.IBinder obj)
    {
      if ((obj==null)) {
        return null;
      }
      android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
      if (((iin!=null)&&(iin instanceof vendor.aospa.biometrics.face.ISenseServiceReceiver))) {
        return ((vendor.aospa.biometrics.face.ISenseServiceReceiver)iin);
      }
      return new vendor.aospa.biometrics.face.ISenseServiceReceiver.Stub.Proxy(obj);
    }
    @Override public android.os.IBinder asBinder()
    {
      return this;
    }
    @Override public boolean onTransact(int code, android.os.Parcel data, android.os.Parcel reply, int flags) throws android.os.RemoteException
    {
      java.lang.String descriptor = DESCRIPTOR;
      if (code >= android.os.IBinder.FIRST_CALL_TRANSACTION && code <= android.os.IBinder.LAST_CALL_TRANSACTION) {
        data.enforceInterface(descriptor);
      }
      if (code == INTERFACE_TRANSACTION) {
        reply.writeString(descriptor);
        return true;
      }
      switch (code)
      {
        case TRANSACTION_onEnrollResult:
        {
          int _arg0;
          _arg0 = data.readInt();
          int _arg1;
          _arg1 = data.readInt();
          int _arg2;
          _arg2 = data.readInt();
          this.onEnrollResult(_arg0, _arg1, _arg2);
          break;
        }
        case TRANSACTION_onAuthenticated:
        {
          int _arg0;
          _arg0 = data.readInt();
          int _arg1;
          _arg1 = data.readInt();
          byte[] _arg2;
          _arg2 = data.createByteArray();
          this.onAuthenticated(_arg0, _arg1, _arg2);
          break;
        }
        case TRANSACTION_onAcquired:
        {
          int _arg0;
          _arg0 = data.readInt();
          int _arg1;
          _arg1 = data.readInt();
          int _arg2;
          _arg2 = data.readInt();
          this.onAcquired(_arg0, _arg1, _arg2);
          break;
        }
        case TRANSACTION_onError:
        {
          int _arg0;
          _arg0 = data.readInt();
          int _arg1;
          _arg1 = data.readInt();
          this.onError(_arg0, _arg1);
          break;
        }
        case TRANSACTION_onRemoved:
        {
          int[] _arg0;
          _arg0 = data.createIntArray();
          int _arg1;
          _arg1 = data.readInt();
          this.onRemoved(_arg0, _arg1);
          break;
        }
        case TRANSACTION_onEnumerate:
        {
          int[] _arg0;
          _arg0 = data.createIntArray();
          int _arg1;
          _arg1 = data.readInt();
          this.onEnumerate(_arg0, _arg1);
          break;
        }
        case TRANSACTION_onLockoutChanged:
        {
          long _arg0;
          _arg0 = data.readLong();
          this.onLockoutChanged(_arg0);
          break;
        }
        default:
        {
          return super.onTransact(code, data, reply, flags);
        }
      }
      return true;
    }
    private static class Proxy implements vendor.aospa.biometrics.face.ISenseServiceReceiver
    {
      private android.os.IBinder mRemote;
      Proxy(android.os.IBinder remote)
      {
        mRemote = remote;
      }
      @Override public android.os.IBinder asBinder()
      {
        return mRemote;
      }
      public java.lang.String getInterfaceDescriptor()
      {
        return DESCRIPTOR;
      }
      @Override public void onEnrollResult(int faceId, int userId, int remaining) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(faceId);
          _data.writeInt(userId);
          _data.writeInt(remaining);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onEnrollResult, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onAuthenticated(int faceId, int userId, byte[] token) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(faceId);
          _data.writeInt(userId);
          _data.writeByteArray(token);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onAuthenticated, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onAcquired(int userId, int acquiredInfo, int vendorCode) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(userId);
          _data.writeInt(acquiredInfo);
          _data.writeInt(vendorCode);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onAcquired, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onError(int error, int vendorCode) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(error);
          _data.writeInt(vendorCode);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onError, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onRemoved(int[] faceIds, int userId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeIntArray(faceIds);
          _data.writeInt(userId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onRemoved, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onEnumerate(int[] faceIds, int userId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeIntArray(faceIds);
          _data.writeInt(userId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onEnumerate, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void onLockoutChanged(long duration) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeLong(duration);
          boolean _status = mRemote.transact(Stub.TRANSACTION_onLockoutChanged, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
    }
    static final int TRANSACTION_onEnrollResult = (android.os.IBinder.FIRST_CALL_TRANSACTION + 0);
    static final int TRANSACTION_onAuthenticated = (android.os.IBinder.FIRST_CALL_TRANSACTION + 1);
    static final int TRANSACTION_onAcquired = (android.os.IBinder.FIRST_CALL_TRANSACTION + 2);
    static final int TRANSACTION_onError = (android.os.IBinder.FIRST_CALL_TRANSACTION + 3);
    static final int TRANSACTION_onRemoved = (android.os.IBinder.FIRST_CALL_TRANSACTION + 4);
    static final int TRANSACTION_onEnumerate = (android.os.IBinder.FIRST_CALL_TRANSACTION + 5);
    static final int TRANSACTION_onLockoutChanged = (android.os.IBinder.FIRST_CALL_TRANSACTION + 6);
  }
  /** @hide */
  public static final java.lang.String DESCRIPTOR = "vendor.aospa.biometrics.face.ISenseServiceReceiver";
  public void onEnrollResult(int faceId, int userId, int remaining) throws android.os.RemoteException;
  public void onAuthenticated(int faceId, int userId, byte[] token) throws android.os.RemoteException;
  public void onAcquired(int userId, int acquiredInfo, int vendorCode) throws android.os.RemoteException;
  public void onError(int error, int vendorCode) throws android.os.RemoteException;
  public void onRemoved(int[] faceIds, int userId) throws android.os.RemoteException;
  public void onEnumerate(int[] faceIds, int userId) throws android.os.RemoteException;
  public void onLockoutChanged(long duration) throws android.os.RemoteException;
}
