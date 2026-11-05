/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/tools/android-15/aidl --lang=java -I/tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/src/ParanoidSense/interfaces/biometrics/face/aidl/src -o gen /tmp/claude-1000/-home-gzcheng-Desktop/eb8c19c5-849e-466b-871d-061b17d306f5/scratchpad/face/src/ParanoidSense/interfaces/biometrics/face/aidl/src/vendor/aospa/biometrics/face/ISenseService.aidl
 */
package vendor.aospa.biometrics.face;
/** @hide */
public interface ISenseService extends android.os.IInterface
{
  /** Default implementation for ISenseService. */
  public static class Default implements vendor.aospa.biometrics.face.ISenseService
  {
    @Override public void authenticate(long operationId) throws android.os.RemoteException
    {
    }
    @Override public void cancel() throws android.os.RemoteException
    {
    }
    @Override public void enroll(byte[] cryptoToken, int timeout, int[] disabledFeatures) throws android.os.RemoteException
    {
    }
    @Override public int enumerate() throws android.os.RemoteException
    {
      return 0;
    }
    @Override public long generateChallenge(int timeout) throws android.os.RemoteException
    {
      return 0L;
    }
    @Override public int getAuthenticatorId() throws android.os.RemoteException
    {
      return 0;
    }
    @Override public void remove(int biometricId) throws android.os.RemoteException
    {
    }
    @Override public void resetLockout(byte[] cryptoToken) throws android.os.RemoteException
    {
    }
    @Override public int revokeChallenge() throws android.os.RemoteException
    {
      return 0;
    }
    @Override public void setCallback(vendor.aospa.biometrics.face.ISenseServiceReceiver receiver) throws android.os.RemoteException
    {
    }
    @Override public int getFeatureCount() throws android.os.RemoteException
    {
      return 0;
    }
    @Override public boolean getFeature(int feature, int faceId) throws android.os.RemoteException
    {
      return false;
    }
    @Override public void setFeature(int feature, boolean enable, byte[] token, int faceId) throws android.os.RemoteException
    {
    }
    @Override
    public android.os.IBinder asBinder() {
      return null;
    }
  }
  /** Local-side IPC implementation stub class. */
  public static abstract class Stub extends android.os.Binder implements vendor.aospa.biometrics.face.ISenseService
  {
    /** Construct the stub at attach it to the interface. */
    @SuppressWarnings("this-escape")
    public Stub()
    {
      this.attachInterface(this, DESCRIPTOR);
    }
    /**
     * Cast an IBinder object into an vendor.aospa.biometrics.face.ISenseService interface,
     * generating a proxy if needed.
     */
    public static vendor.aospa.biometrics.face.ISenseService asInterface(android.os.IBinder obj)
    {
      if ((obj==null)) {
        return null;
      }
      android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
      if (((iin!=null)&&(iin instanceof vendor.aospa.biometrics.face.ISenseService))) {
        return ((vendor.aospa.biometrics.face.ISenseService)iin);
      }
      return new vendor.aospa.biometrics.face.ISenseService.Stub.Proxy(obj);
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
        case TRANSACTION_authenticate:
        {
          long _arg0;
          _arg0 = data.readLong();
          this.authenticate(_arg0);
          break;
        }
        case TRANSACTION_cancel:
        {
          this.cancel();
          break;
        }
        case TRANSACTION_enroll:
        {
          byte[] _arg0;
          _arg0 = data.createByteArray();
          int _arg1;
          _arg1 = data.readInt();
          int[] _arg2;
          _arg2 = data.createIntArray();
          this.enroll(_arg0, _arg1, _arg2);
          break;
        }
        case TRANSACTION_enumerate:
        {
          int _result = this.enumerate();
          reply.writeNoException();
          reply.writeInt(_result);
          break;
        }
        case TRANSACTION_generateChallenge:
        {
          int _arg0;
          _arg0 = data.readInt();
          long _result = this.generateChallenge(_arg0);
          reply.writeNoException();
          reply.writeLong(_result);
          break;
        }
        case TRANSACTION_getAuthenticatorId:
        {
          int _result = this.getAuthenticatorId();
          reply.writeNoException();
          reply.writeInt(_result);
          break;
        }
        case TRANSACTION_remove:
        {
          int _arg0;
          _arg0 = data.readInt();
          this.remove(_arg0);
          break;
        }
        case TRANSACTION_resetLockout:
        {
          byte[] _arg0;
          _arg0 = data.createByteArray();
          this.resetLockout(_arg0);
          break;
        }
        case TRANSACTION_revokeChallenge:
        {
          int _result = this.revokeChallenge();
          reply.writeNoException();
          reply.writeInt(_result);
          break;
        }
        case TRANSACTION_setCallback:
        {
          vendor.aospa.biometrics.face.ISenseServiceReceiver _arg0;
          _arg0 = vendor.aospa.biometrics.face.ISenseServiceReceiver.Stub.asInterface(data.readStrongBinder());
          this.setCallback(_arg0);
          break;
        }
        case TRANSACTION_getFeatureCount:
        {
          int _result = this.getFeatureCount();
          reply.writeNoException();
          reply.writeInt(_result);
          break;
        }
        case TRANSACTION_getFeature:
        {
          int _arg0;
          _arg0 = data.readInt();
          int _arg1;
          _arg1 = data.readInt();
          boolean _result = this.getFeature(_arg0, _arg1);
          reply.writeNoException();
          reply.writeInt(((_result)?(1):(0)));
          break;
        }
        case TRANSACTION_setFeature:
        {
          int _arg0;
          _arg0 = data.readInt();
          boolean _arg1;
          _arg1 = (0!=data.readInt());
          byte[] _arg2;
          _arg2 = data.createByteArray();
          int _arg3;
          _arg3 = data.readInt();
          this.setFeature(_arg0, _arg1, _arg2, _arg3);
          break;
        }
        default:
        {
          return super.onTransact(code, data, reply, flags);
        }
      }
      return true;
    }
    private static class Proxy implements vendor.aospa.biometrics.face.ISenseService
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
      @Override public void authenticate(long operationId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeLong(operationId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_authenticate, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void cancel() throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          boolean _status = mRemote.transact(Stub.TRANSACTION_cancel, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void enroll(byte[] cryptoToken, int timeout, int[] disabledFeatures) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeByteArray(cryptoToken);
          _data.writeInt(timeout);
          _data.writeIntArray(disabledFeatures);
          boolean _status = mRemote.transact(Stub.TRANSACTION_enroll, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public int enumerate() throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        int _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          boolean _status = mRemote.transact(Stub.TRANSACTION_enumerate, _data, _reply, 0);
          _reply.readException();
          _result = _reply.readInt();
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public long generateChallenge(int timeout) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        long _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(timeout);
          boolean _status = mRemote.transact(Stub.TRANSACTION_generateChallenge, _data, _reply, 0);
          _reply.readException();
          _result = _reply.readLong();
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public int getAuthenticatorId() throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        int _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          boolean _status = mRemote.transact(Stub.TRANSACTION_getAuthenticatorId, _data, _reply, 0);
          _reply.readException();
          _result = _reply.readInt();
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public void remove(int biometricId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(biometricId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_remove, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public void resetLockout(byte[] cryptoToken) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeByteArray(cryptoToken);
          boolean _status = mRemote.transact(Stub.TRANSACTION_resetLockout, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public int revokeChallenge() throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        int _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          boolean _status = mRemote.transact(Stub.TRANSACTION_revokeChallenge, _data, _reply, 0);
          _reply.readException();
          _result = _reply.readInt();
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public void setCallback(vendor.aospa.biometrics.face.ISenseServiceReceiver receiver) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeStrongInterface(receiver);
          boolean _status = mRemote.transact(Stub.TRANSACTION_setCallback, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
      @Override public int getFeatureCount() throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        int _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          boolean _status = mRemote.transact(Stub.TRANSACTION_getFeatureCount, _data, _reply, 0);
          _reply.readException();
          _result = _reply.readInt();
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public boolean getFeature(int feature, int faceId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        android.os.Parcel _reply = android.os.Parcel.obtain();
        boolean _result;
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(feature);
          _data.writeInt(faceId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_getFeature, _data, _reply, 0);
          _reply.readException();
          _result = (0!=_reply.readInt());
        }
        finally {
          _reply.recycle();
          _data.recycle();
        }
        return _result;
      }
      @Override public void setFeature(int feature, boolean enable, byte[] token, int faceId) throws android.os.RemoteException
      {
        android.os.Parcel _data = android.os.Parcel.obtain();
        try {
          _data.writeInterfaceToken(DESCRIPTOR);
          _data.writeInt(feature);
          _data.writeInt(((enable)?(1):(0)));
          _data.writeByteArray(token);
          _data.writeInt(faceId);
          boolean _status = mRemote.transact(Stub.TRANSACTION_setFeature, _data, null, android.os.IBinder.FLAG_ONEWAY);
        }
        finally {
          _data.recycle();
        }
      }
    }
    static final int TRANSACTION_authenticate = (android.os.IBinder.FIRST_CALL_TRANSACTION + 0);
    static final int TRANSACTION_cancel = (android.os.IBinder.FIRST_CALL_TRANSACTION + 1);
    static final int TRANSACTION_enroll = (android.os.IBinder.FIRST_CALL_TRANSACTION + 2);
    static final int TRANSACTION_enumerate = (android.os.IBinder.FIRST_CALL_TRANSACTION + 3);
    static final int TRANSACTION_generateChallenge = (android.os.IBinder.FIRST_CALL_TRANSACTION + 4);
    static final int TRANSACTION_getAuthenticatorId = (android.os.IBinder.FIRST_CALL_TRANSACTION + 5);
    static final int TRANSACTION_remove = (android.os.IBinder.FIRST_CALL_TRANSACTION + 6);
    static final int TRANSACTION_resetLockout = (android.os.IBinder.FIRST_CALL_TRANSACTION + 7);
    static final int TRANSACTION_revokeChallenge = (android.os.IBinder.FIRST_CALL_TRANSACTION + 8);
    static final int TRANSACTION_setCallback = (android.os.IBinder.FIRST_CALL_TRANSACTION + 9);
    static final int TRANSACTION_getFeatureCount = (android.os.IBinder.FIRST_CALL_TRANSACTION + 10);
    static final int TRANSACTION_getFeature = (android.os.IBinder.FIRST_CALL_TRANSACTION + 11);
    static final int TRANSACTION_setFeature = (android.os.IBinder.FIRST_CALL_TRANSACTION + 12);
  }
  /** @hide */
  public static final java.lang.String DESCRIPTOR = "vendor.aospa.biometrics.face.ISenseService";
  public void authenticate(long operationId) throws android.os.RemoteException;
  public void cancel() throws android.os.RemoteException;
  public void enroll(byte[] cryptoToken, int timeout, int[] disabledFeatures) throws android.os.RemoteException;
  public int enumerate() throws android.os.RemoteException;
  public long generateChallenge(int timeout) throws android.os.RemoteException;
  public int getAuthenticatorId() throws android.os.RemoteException;
  public void remove(int biometricId) throws android.os.RemoteException;
  public void resetLockout(byte[] cryptoToken) throws android.os.RemoteException;
  public int revokeChallenge() throws android.os.RemoteException;
  public void setCallback(vendor.aospa.biometrics.face.ISenseServiceReceiver receiver) throws android.os.RemoteException;
  public int getFeatureCount() throws android.os.RemoteException;
  public boolean getFeature(int feature, int faceId) throws android.os.RemoteException;
  public void setFeature(int feature, boolean enable, byte[] token, int faceId) throws android.os.RemoteException;
}
