# kotlinx.serialization keeps its generated serializers through its own rules;
# the wire types are read by name, so keep their companions.
-keepclassmembers @kotlinx.serialization.Serializable class com.wainhq.wain.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
